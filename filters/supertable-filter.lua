--[[
Pandoc Lua filter to convert tables to supertabular format.
Supertabular works better than longtable in double-column formats.

Usage:
    pandoc input.md -o output.tex --lua-filter supertabular.lua
]]

local function add_header_includes(meta)
  local header_includes = meta['header-includes']

  if not header_includes then
    header_includes = pandoc.MetaList{}
  elseif header_includes.t ~= 'MetaList' then
    header_includes = pandoc.MetaList{header_includes}
  end

  local packages = {
    pandoc.RawBlock('latex', '\\usepackage{supertabular}'),
    pandoc.RawBlock('latex', '\\usepackage{array}')
  }

  for _, pkg in ipairs(packages) do
    header_includes:insert(pandoc.MetaBlocks{pkg})
  end

  meta['header-includes'] = header_includes
  return meta
end

local function align_to_latex(align)
  if align == 'AlignLeft' then
    return 'l'
  elseif align == 'AlignRight' then
    return 'r'
  elseif align == 'AlignCenter' then
    return 'c'
  else
    return 'l'
  end
end

local function process_inlines(inlines)
  -- Process inline elements and preserve LaTeX math and code
  local result = {}
  for _, inline in ipairs(inlines) do
    -- Debug: print inline type
    io.stderr:write('    [Inline type: ' .. inline.t .. '] ')

    if inline.t == 'Math' then
      if inline.mathtype == 'InlineMath' then
        table.insert(result, '$' .. inline.text .. '$')
      else
        table.insert(result, '$$' .. inline.text .. '$$')
      end
    elseif inline.t == 'Code' then
      -- Preserve inline code as \texttt{}
      local code_text = inline.text
      io.stderr:write('Code content: "' .. code_text .. '" ')
      -- Escape backslashes in code for LaTeX
      code_text = code_text:gsub('\\', '\\textbackslash{}')
      table.insert(result, '\\texttt{' .. code_text .. '}')
    elseif inline.t == 'Str' then
      local text = inline.text
      -- Escape standalone $ (used as currency symbol)
      if text == '$' then
        text = '\\$'
      end
      table.insert(result, text)
    elseif inline.t == 'Space' then
      table.insert(result, ' ')
    else
      -- For other inline elements, use pandoc's stringify
      table.insert(result, pandoc.utils.stringify(inline))
    end
  end
  return table.concat(result)
end

local function stringify_with_math(blocks)
  -- Process blocks (cell contents) and extract inlines with math preserved
  local result = {}
  for _, block in ipairs(blocks) do
    if block.t == 'Plain' or block.t == 'Para' then
      table.insert(result, process_inlines(block.content))
    else
      -- Fallback for other block types
      table.insert(result, pandoc.utils.stringify(block))
    end
  end
  return table.concat(result, ' ')
end

local function table_to_supertabular(tbl)
  local latex = {}

  -- Extract caption with math support
  local caption = ''
  if tbl.caption and tbl.caption.long then
    for _, block in ipairs(tbl.caption.long) do
      if block.content then
        caption = process_inlines(block.content)
        break
      end
    end
  end

  -- Extract label from table identifier
  local label = ''
  if tbl.identifier and tbl.identifier ~= '' then
    label = tbl.identifier
  end

  -- Debug output
  io.stderr:write('\n=== TABLE DETECTED ===\n')
  io.stderr:write('Caption: ')
  io.stderr:write(caption)
  io.stderr:write('\n')
  io.stderr:write('Label: ')
  io.stderr:write(label)
  io.stderr:write('\n')
  io.stderr:write('Number of columns: ' .. tostring(#tbl.colspecs) .. '\n')

  -- Build column specification
  local col_spec = {}
  for i, spec in ipairs(tbl.colspecs) do
    local align = align_to_latex(spec[1])
    table.insert(col_spec, align)
    io.stderr:write('Column ' .. tostring(i) .. ' alignment: ' .. align .. '\n')
  end
  local col_format = '|' .. table.concat(col_spec, '|') .. '|'
  io.stderr:write('Column format: ' .. col_format .. '\n')

  -- Start table environment with caption if present
  if caption ~= '' then
    table.insert(latex, '\\begin{table}[htbp]')
    table.insert(latex, '\\centering')
    -- Add label if present
    if label ~= '' then
      table.insert(latex, '\\caption{' .. caption .. '}\\label{' .. label .. '}')
    else
      table.insert(latex, '\\caption{' .. caption .. '}')
    end
  end

  -- Begin supertabular
  table.insert(latex, '\\begin{supertabular}{' .. col_format .. '}')
  table.insert(latex, '\\hline')

  -- Process table head
  if tbl.head and tbl.head.rows then
    io.stderr:write('Header rows: ' .. tostring(#tbl.head.rows) .. '\n')
    for row_idx, row in ipairs(tbl.head.rows) do
      local cells = {}
      io.stderr:write('  Header row ' .. tostring(row_idx) .. ': ')
      for _, cell in ipairs(row.cells) do
        local cell_text = stringify_with_math(cell.contents)
        -- Use \bfseries for bold that works with math mode
        table.insert(cells, '{\\bfseries ' .. cell_text .. '}')
        io.stderr:write('[' .. cell_text:gsub('\n', ' ') .. '] ')
      end
      io.stderr:write('\n')
      table.insert(latex, table.concat(cells, ' & ') .. ' \\\\')
      table.insert(latex, '\\hline')
    end
  else
    io.stderr:write('No header rows found\n')
  end

  -- Process table bodies
  io.stderr:write('Body sections: ' .. tostring(#tbl.bodies) .. '\n')
  for body_idx, body in ipairs(tbl.bodies) do
    io.stderr:write('Body ' .. tostring(body_idx) .. ' rows: ' .. tostring(#body.body) .. '\n')
    for row_idx, row in ipairs(body.body) do
      local cells = {}
      io.stderr:write('  Body row ' .. tostring(row_idx) .. ': ')
      for _, cell in ipairs(row.cells) do
        local cell_text = stringify_with_math(cell.contents)
        table.insert(cells, cell_text)
        io.stderr:write('[' .. cell_text:gsub('\n', ' ') .. '] ')
      end
      io.stderr:write('\n')
      table.insert(latex, table.concat(cells, ' & ') .. ' \\\\')
      table.insert(latex, '\\hline')
    end
  end

  -- End supertabular
  table.insert(latex, '\\end{supertabular}')

  if caption ~= '' then
    table.insert(latex, '\\end{table}')
  end

  io.stderr:write('=== END TABLE ===\n\n')

  return pandoc.RawBlock('latex', table.concat(latex, '\n'))
end

return {
  {Meta = add_header_includes},
  {Table = table_to_supertabular}
}
