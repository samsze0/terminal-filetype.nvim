-- Tweak of:
-- https://github.com/norcalli/nvim-terminal.lua

local utils = require("utils")
local color_utils = require("utils.colors")

local HIGHLIGHT_NAME_PREFIX = "terminalft"
local namespace = vim.api.nvim_create_namespace("terminal-filetype")
local autocmd_group =
  vim.api.nvim_create_augroup("terminal-filetype", { clear = true })

local debug = os.getenv("TERMINAL_FT_NVIM_DEBUG") -- Hinders performance. Toggle on only when needed

local notifier = {
  debug = function(message)
    vim.notify(message, vim.log.levels.DEBUG)
  end,
  info = function(message)
    vim.notify(message, vim.log.levels.INFO)
  end,
  warn = function(message)
    vim.notify(message, vim.log.levels.WARN)
  end,
  error = function(message)
    vim.notify(message, vim.log.levels.ERROR)
  end,
}

local config = {
  notifier = notifier
}

-- TODO: populate rgb_color_table
local rgb_color_table = {}

-- TODO: support more escope codes
-- https://github.com/norcalli/nvim-terminal.lua/issues/8

local M = {}

---@alias TerminalFiletypeHighlightAttributes { gui?: table<string, boolean>, guifg?: string, guibg?: string, guisp?: string }

-- Process a color code and mutate the existing highlight attributes
--
---@param rgb_color_table table<number, string>
---@param code number | string
---@param current_attributes TerminalFiletypeHighlightAttributes
---@return TerminalFiletypeHighlightAttributes
local function process_color(rgb_color_table, code, current_attributes)
  if debug then
    notifier.debug("Processing color")
  end

  current_attributes = current_attributes or {}

  ---@type number
  local c = type(code) ~= "number" and tonumber(code) or code ---@diagnostic disable-line: assign-type-mismatch
  if c == nil then error("Invalid code: " .. vim.inspect(c)) end

  if c >= 30 and c <= 37 then
    -- Foreground color
    current_attributes.guifg = rgb_color_table[c - 30]
  elseif c >= 40 and c <= 47 then
    -- Background color
    current_attributes.guibg = rgb_color_table[c - 40]
  elseif c >= 90 and c <= 97 then
    -- Bright colors. Foreground
    current_attributes.guifg = rgb_color_table[c - 90 + 8]
  elseif c >= 100 and c <= 107 then
    -- Bright colors. Background
    current_attributes.guibg = rgb_color_table[c - 100 + 8]
  elseif c == 39 then
    -- Reset to normal color for foreground
    current_attributes.guifg = "fg"
  elseif c == 49 then
    -- Reset to normal color for background
    current_attributes.guibg = "bg"
  elseif c >= 1 and c <= 29 then
    -- Gui
    current_attributes.gui = current_attributes.gui or {}

    if c == 9 then
      current_attributes.gui.strikethrough = true
    elseif c == 29 then
      current_attributes.gui.strikethrough = false
    elseif c == 7 then
      current_attributes.gui.reverse = true
    elseif c == 27 then
      current_attributes.gui.reverse = false
    elseif c == 4 then
      current_attributes.gui.underline = true
    elseif c == 24 then
      current_attributes.gui.underline = false
    elseif c == 3 then
      current_attributes.gui.italic = true
    elseif c == 23 then
      current_attributes.gui.italic = false
    elseif c == 1 then
      current_attributes.gui.bold = true
    elseif c == 22 then
      current_attributes.gui.bold = false
    end
  elseif c == 0 then
    -- RESET
    current_attributes = {}
  end

  if debug then
    notifier.debug(utils.str_fmt("Processed color", { current_attributes = current_attributes }))
  end
  return current_attributes
end

-- Format the gui attributes as string by concatenating active attributes
--
---@param gui_attributes table<string, boolean>
---@param delimiter? string
---@return string
local function format_gui_attribute(gui_attributes, delimiter)
  delimiter = delimiter or ","

  local result = table.concat(
    utils.filter(gui_attributes, function(k, v) return v end),
    delimiter
  )

  if result == "" then result = "NONE" end

  return result
end

-- Process a code sequence and mutate the existing attributes
--
---@param rgb_color_table table<number, string>
---@param code_seq string
---@param current_attributes TerminalFiletypeHighlightAttributes
---@return TerminalFiletypeHighlightAttributes?
local function process_code_seq(rgb_color_table, code_seq, current_attributes)
  if debug then
    notifier.debug(utils.str_fmt(
      "Processing code",
      { code = code_seq, current_attributes = current_attributes }
    ))
  end

  -- CSI "m" is equivalent to CSI "0m", which is Reset, which means null the attributes
  if #code_seq == 0 then return {} end

  local matches = code_seq:find(";")
  if not matches then
    return process_color(rgb_color_table, code_seq, current_attributes)
  end

  local find_start = 1
  while find_start <= #code_seq do
    local match_start, match_end = code_seq:find(";", find_start)
    local segment = code_seq:sub(find_start, match_start and match_start - 1)
    if not match_start then
      process_color(rgb_color_table, segment, current_attributes)
      return current_attributes
    end

    if segment ~= "38" and segment ~= "48" then
      process_color(rgb_color_table, segment, current_attributes)
      find_start = match_end + 1
      goto continue
    end

    local is_foreground = segment == "38"
    -- Verify the segment start. The only possibilities are 2, 5
    segment = code_seq:sub(find_start + #"38", find_start + #"38;2;" - 1)
    if segment == ";5;" or segment == ":5:" then
      local color_segment = code_seq:sub(find_start + #"38;2;"):match("^(%d+)")
      if not color_segment then

        notifier.error("Invalid color code: " .. code_seq:sub(find_start))
        return
      end
      local color_code = tonumber(color_segment)
      find_start = find_start + #"38;5;" + #color_segment + 1
      if not color_code or color_code > 255 then
        notifier.error("Invalid color code: " .. color_code)
        return
      elseif is_foreground then
        current_attributes.guifg = rgb_color_table[color_code]
      else
        current_attributes.guibg = rgb_color_table[color_code]
      end
    elseif segment == ";2;" or segment == ":2:" then
      local separator = segment:sub(1, 1)
      local r, g, b, len = code_seq:sub(find_start + #"38;2;"):match(
        "^(%d+)" .. separator .. "(%d+)" .. separator .. "(%d+)()"
      )
      if not r then
        notifier.error("Invalid color code: " .. code_seq:sub(find_start))
        return
      end
      r, g, b = tonumber(r), tonumber(g), tonumber(b)
      find_start = find_start + #"38;2;" + len
      if not r or not g or not b or r > 255 or g > 255 or b > 255 then
        notifier.error("Invalid color code: " .. r .. ", " .. g .. ", " .. b)
        return
      else
        current_attributes[is_foreground and "guifg" or "guibg"] =
          color_utils.rgb_to_hex(r, g, b)
      end
    else
      notifier.error("Invalid color code: " .. code_seq:sub(find_start))
      return
    end
    ::continue::
  end

  if debug then
    notifier.debug(utils.str_fmt("Processed code", { current_attributes = current_attributes }))
  end
  return current_attributes
end

---@param attributes TerminalFiletypeHighlightAttributes
---@return string
local function make_unique_hlgroup_name(attributes)
  local result = { HIGHLIGHT_NAME_PREFIX }
  if attributes.gui then
    table.insert(result, "g")
    table.insert(result, format_gui_attribute(attributes.gui, "_"))
  end
  if attributes.guifg then
    table.insert(result, "gfg")
    table.insert(result, (attributes.guifg:gsub("^#", "")))
  end
  if attributes.guibg then
    table.insert(result, "gbg")
    table.insert(result, (attributes.guibg:gsub("^#", "")))
  end
  if attributes.guisp then
    table.insert(result, "gsp")
    table.insert(result, (attributes.guisp:gsub("^#", "")))
  end
  return table.concat(result, "_")
end

---@param t table
---@return boolean
local function table_is_empty(t) return next(t) == nil end

---@param buf number
---@param attributes TerminalFiletypeHighlightAttributes
---@return string
local function create_highlight_group(buf, attributes)
  if debug then
    notifier.debug(utils.str_fmt("Creating highlight group", { attributes = attributes }))
  end

  if table_is_empty(attributes) then return "Normal" end
  local hl_group = make_unique_hlgroup_name(attributes)

  local val = {}
  val.fg = attributes.guifg
  val.bg = attributes.guibg
  val.sp = attributes.guisp
  if attributes.gui then
    for k, v in pairs(attributes.gui) do
      val[k] = v
    end
  end

  vim.api.nvim_set_hl(buf, hl_group, val)

  return hl_group
end

---@param buf number
---@param current_attributes TerminalFiletypeHighlightAttributes
---@param region_line_start number
---@param region_byte_start number
---@param region_line_end number
---@param region_byte_end number
local function create_highlight(
  buf,
  current_attributes,
  region_line_start,
  region_byte_start,
  region_line_end,
  region_byte_end
)
  if debug then
    notifier.debug(utils.str_fmt("Creating highlight", {
      buf = buf,
      current_attributes = current_attributes,
      region_line_start = region_line_start,
      region_byte_start = region_byte_start,
      region_line_end = region_line_end,
      region_byte_end = region_byte_end,
    }))
  end

  local highlight_name = create_highlight_group(buf, current_attributes)
  if region_line_start == region_line_end then
    vim.api.nvim_buf_add_highlight(
      buf,
      namespace,
      highlight_name,
      region_line_start,
      region_byte_start,
      region_byte_end
    )
  else
    vim.api.nvim_buf_add_highlight(
      buf,
      namespace,
      highlight_name,
      region_line_start,
      region_byte_start,
      -1
    )
    for linenum = region_line_start + 1, region_line_end - 1 do
      vim.api.nvim_buf_add_highlight(
        buf,
        namespace,
        highlight_name,
        linenum,
        0,
        -1
      )
    end
    vim.api.nvim_buf_add_highlight(
      buf,
      namespace,
      highlight_name,
      region_line_end,
      0,
      region_byte_end
    )
  end
end

-- Apply highlight to the buffer
--
---@param buf number
---@param rgb_color_table table<number, string>
---@return nil
local function highlight_buffer(buf, rgb_color_table)
  if debug then notifier.debug(utils.str_fmt("Highlighting buffer", { buf = buf })) end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, true)

  local current_region, current_attributes = nil, {}
  for i, line in ipairs(lines) do
    for match_start, code_seq, match_end in line:gmatch("()%[([%d;:]*[mK])()") do
      if current_region then
        create_highlight(
          buf,
          current_attributes,
          current_region.line - 1,
          current_region.col - 1,
          i - 1,
          match_start - 1
        )
      end
      current_region = { line = i, col = match_start }

      -- Check the last character of the code sequence to see if it's a "m" or "K"
      ---@cast code_seq string
      if code_seq:sub(-1) == "m" then
        code_seq = code_seq:sub(1, -2) -- Remove the last character
        ---@diagnostic disable-next-line: cast-local-type
        current_attributes =
          process_code_seq(rgb_color_table, code_seq, current_attributes)
        if not current_attributes then error("Fail to parse code sequence") end
      else
        current_attributes = {}
      end
    end
  end
  if current_region then
    create_highlight(
      buf,
      current_attributes,
      current_region.line - 1,
      current_region.col - 1,
      #lines - 1,
      -1
    )
  end
end

---@param buf number
M.refresh_highlight = function(buf)
  vim.api.nvim_buf_call(buf, function()
    if vim.bo.filetype ~= "terminal" then error("Invalid filetype") end

    vim.api.nvim_buf_clear_namespace(0, namespace, 0, -1)
    highlight_buffer(0, rgb_color_table)
  end)
end

---@alias TerminalFiletypeOptions { notifier?: { debug: fun(message: string), info: fun(message: string), warn: fun(message: string), error: fun(message: string) } }
---@param opts? TerminalFiletypeOptions
M.setup = function(opts)
  config = utils.opts_deep_extend(config, opts)
  ---@cast opts TerminalFiletypeOptions

  -- FIX: autocmd not applying highlight correctly. For now plugin users have to call refresh_highlight manually
  -- vim.api.nvim_create_autocmd({
  --   "FileType",
  -- }, {
  --   group = autocmd_group,
  --   callback = function(ctx)
  --     M.refresh_highlight(0)
  --   end,
  -- })
end

return M
