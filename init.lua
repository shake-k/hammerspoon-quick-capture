-- Dropbox-macOS quick-capture (production)
-- Option+Space opens a centered modal (title + body). Save writes a
-- vault-compliant Markdown file to ~/second-brain-mk1/_inbox/.
-- Phase 3 spike validated bind + webview + JS->Lua bridge. Phase 4 adds
-- file write with YAML frontmatter, slug filename, and collision-safe naming.

local M = {}

-- Module-level references to prevent garbage collection of the webview.
M.webview = nil
M.controller = nil

local INBOX = os.getenv("HOME") .. "/second-brain-mk1/_inbox/"

local HTML = [[
<!doctype html>
<html><head><meta charset="utf-8"><style>
  body { font-family: -apple-system, sans-serif; margin: 0; padding: 16px;
         background: #1e1e1e; color: #eee; }
  input, textarea { width: 100%; box-sizing: border-box; padding: 8px;
                    font-size: 14px; background: #2a2a2a; color: #eee;
                    border: 1px solid #444; border-radius: 4px; margin-bottom: 8px; }
  textarea { height: 140px; resize: none; }
  .row { display: flex; justify-content: flex-end; gap: 8px; }
  button { padding: 6px 14px; font-size: 13px; border-radius: 4px;
           border: 1px solid #555; background: #333; color: #eee; cursor: pointer; }
  button.primary { background: #0a84ff; border-color: #0a84ff; }
</style></head><body>
  <input id="title" placeholder="Title" autofocus />
  <textarea id="body" placeholder="Body"></textarea>
  <div class="row">
    <button onclick="cancel()">Cancel</button>
    <button class="primary" onclick="save()">Save</button>
  </div>
<script>
  function send(action) {
    var t = document.getElementById('title').value;
    var b = document.getElementById('body').value;
    try {
      webkit.messageHandlers.dropbox.postMessage({action: action, title: t, body: b});
    } catch (err) { console.log('controller missing: ' + err); }
  }
  function save() { send('save'); }
  function cancel() { send('cancel'); }
  document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') { cancel(); }
    if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) { save(); }
  });
  // Focus title on load
  window.addEventListener('load', function() {
    document.getElementById('title').focus();
  });
</script>
</body></html>
]]

-- slugify: title -> filesystem-safe slug.
-- lowercase, non-alphanumeric -> "-", collapse repeats, trim "-", truncate to 40.
-- Empty/whitespace-only input -> "untitled".
local function slugify(title)
  if not title or title == "" then return "untitled" end
  local s = title:lower()
  -- Replace any run of non-alphanumeric (ASCII) with "-"
  s = s:gsub("[^a-z0-9]+", "-")
  -- Trim leading/trailing dashes
  s = s:gsub("^%-+", ""):gsub("%-+$", "")
  if s == "" then return "untitled" end
  if #s > 40 then
    s = s:sub(1, 40)
    s = s:gsub("%-+$", "")
  end
  if s == "" then return "untitled" end
  return s
end

-- escapeYaml: produce the inner body of a double-quoted YAML scalar
-- (caller wraps in quotes). Escapes \ then ". Strips newlines defensively
-- (title is a single-line <input>).
local function escapeYaml(value)
  if not value then return "" end
  value = value:gsub("[\r\n]+", " ")
  value = value:gsub("\\", "\\\\")
  value = value:gsub("\"", "\\\"")
  return value
end

-- buildFrontmatter: produce the YAML block (with --- fences and trailing newline).
-- title: raw title string (may be empty). captureTime: os.time() value used to
-- format updated and (when title is empty) the "Quick capture HH:MM" summary.
local function buildFrontmatter(title, captureTime)
  local summary
  if title and title ~= "" then
    summary = escapeYaml(title)
  else
    summary = "Quick capture " .. os.date("%H:%M", captureTime)
  end
  local dateStr = os.date("%Y-%m-%d", captureTime)
  return table.concat({
    "---",
    "type: knowledge",
    "summary: \"" .. summary .. "\"",
    "tags: [inbox]",
    "status: draft",
    "updated: " .. dateStr,
    "---",
    "",
  }, "\n")
end

-- nextAvailablePath: given a base path (without .md), return a path that does
-- not yet exist on disk. Tries base.md, base-2.md, base-3.md, ...
local function nextAvailablePath(baseNoExt)
  local candidate = baseNoExt .. ".md"
  local i = 2
  while hs.fs.attributes(candidate) ~= nil do
    candidate = baseNoExt .. "-" .. i .. ".md"
    i = i + 1
  end
  return candidate
end

-- writeCapture: orchestrate filename + frontmatter + write. Returns (path, nil)
-- on success or (nil, errMsg) on failure. Errors out loudly if INBOX is missing.
local function writeCapture(title, body)
  local attr = hs.fs.attributes(INBOX)
  if not attr or attr.mode ~= "directory" then
    return nil, "inbox directory missing: " .. INBOX
  end

  local captureTime = os.time()
  local slug = slugify(title or "")
  local stamp = os.date("%Y-%m-%d-%H%M%S", captureTime)
  local baseNoExt = INBOX .. stamp .. "-" .. slug
  local path = nextAvailablePath(baseNoExt)

  local frontmatter = buildFrontmatter(title or "", captureTime)
  local contents = frontmatter .. (body or "")

  local f, err = io.open(path, "w")
  if not f then
    return nil, tostring(err)
  end
  f:write(contents)
  f:close()
  return path, nil
end

local function closeWebview()
  if M.webview then
    M.webview:delete()
    M.webview = nil
    M.controller = nil
  end
end

local function showCapture()
  -- If already open, close first to avoid stacking.
  if M.webview then closeWebview() end

  M.controller = hs.webview.usercontent.new("dropbox")
  M.controller:setCallback(function(msg)
    local payload = msg.body or msg
    if type(payload) ~= "table" then
      print("dropbox-macos: unexpected payload type=" .. type(payload))
      closeWebview()
      return
    end

    if payload.action ~= "save" then
      -- cancel / escape / unknown non-save action
      closeWebview()
      return
    end

    local title = payload.title or ""
    local body = payload.body or ""

    -- Both empty -> treat as cancel. No file, no alert.
    if title == "" and body == "" then
      closeWebview()
      return
    end

    local path, err = writeCapture(title, body)
    if not path then
      print("dropbox-macos: capture failed: " .. tostring(err))
      hs.alert.show("✗ Capture failed: " .. tostring(err), 4)
      -- Do NOT close modal — let user retry with content intact.
      return
    end

    local label = (title ~= "" and title) or "untitled"
    hs.alert.show("✓ Captured: " .. label, 1.5)
    closeWebview()
  end)

  local screen = hs.screen.mainScreen():frame()
  local w, h = 500, 300
  local rect = {
    x = screen.x + (screen.w - w) / 2,
    y = screen.y + (screen.h - h) / 2,
    w = w, h = h,
  }

  M.webview = hs.webview.new(rect, { developerExtrasEnabled = true }, M.controller)
    :windowStyle({"titled", "closable"})
    :allowTextEntry(true)
    :level(hs.drawing.windowLevels.modalPanel)
    :html(HTML)
    :show()
  M.webview:bringToFront(true)
  -- Force key-window focus so the embedded <input autofocus> actually receives
  -- keystrokes even when triggered from another foreground app (Obsidian, iTerm2).
  -- :bringToFront() only adjusts z-order; :focus() on the underlying hs.window
  -- makes it the key window and activates Hammerspoon.
  hs.timer.doAfter(0.05, function()
    local hswin = M.webview and M.webview:hswindow()
    if hswin then hswin:focus() end
  end)
end

-- Expose helpers on the module table so Seth can unit-test from the console.
M.slugify = slugify
M.escapeYaml = escapeYaml
M.buildFrontmatter = buildFrontmatter
M.nextAvailablePath = nextAvailablePath
M.writeCapture = writeCapture
M.showCapture = showCapture

hs.hotkey.bind({"alt"}, "space", showCapture)

return M

-- Manual unit tests — paste into Hammerspoon Console.
-- Helpers are local-scoped but exposed on the module table M. After
-- hs.reload(), re-load the file with dofile to get a handle on M.
--
-- Setup:
--   local M = dofile(os.getenv("HOME") .. "/.hammerspoon/init.lua")
--
-- 1) slugify basic
--   print(M.slugify("Hello, World!"))         -- expected: hello-world
-- 2) slugify collapse + trim
--   print(M.slugify("  ---Foo___Bar!!!  "))   -- expected: foo-bar
-- 3) slugify empty / non-alnum only
--   print(M.slugify(""))                       -- expected: untitled
--   print(M.slugify("!!!---???"))              -- expected: untitled
-- 4) slugify truncate to 40 (length check)
--   print(#M.slugify(string.rep("a", 60)))     -- expected: 40
-- 5) escapeYaml escapes " and backslash
--   print(M.escapeYaml('she said "hi" \\ path'))
--     -- expected: she said \"hi\" \\ path
-- 6) escapeYaml strips newlines
--   print(M.escapeYaml("line1\nline2"))        -- expected: line1 line2
-- 7) buildFrontmatter with title
--   local t = os.time({year=2026,month=5,day=12,hour=9,min=30,sec=0})
--   print(M.buildFrontmatter("My Note", t))
--     -- expected block:
--     -- ---
--     -- type: knowledge
--     -- summary: "My Note"
--     -- tags: [inbox]
--     -- status: draft
--     -- updated: 2026-05-12
--     -- ---
-- 8) buildFrontmatter empty title -> "Quick capture HH:MM"
--   print(M.buildFrontmatter("", t))
--     -- expected summary line: summary: "Quick capture 09:30"
