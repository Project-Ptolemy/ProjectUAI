--[[
      :::       :::    :::     :::      :::::::: ::::::::::: :::::::::
     :+:       :+:    :+:   :+: :+:   :+:    :+:    :+:     :+:    :+:
    +:+       +:+    +:+  +:+   +:+  +:+           +:+     +:+    +:+
   +#+       +#+    +:+ +#++:++#++: +#+           +#+     +#+    +:+
  +#+       +#+    +#+ +#+     +#+ +#+           +#+     +#+    +#+
 #+#       #+#    #+# #+#     #+# #+#    #+#    #+#     #+#    #+#
########## ########  ###     ###  ######## ########### #########

    Docs: https://luacid.dev/docs
    https://discord.gg/KguTgHb3sv
]]

assert(getscriptbytecode, "No getscriptbytecode function found. Please use a supported environment.")

local HttpService = game:GetService("HttpService")

_G.DecompilerKey = _G.DecompilerKey or nil

_G.DecompilerOptions = _G.DecompilerOptions or {
    type_annotations = "functions",
    generated_names = "readable",
    indent = "tab",
}

if _G.DecompilerTelemetry == nil then
    _G.DecompilerTelemetry = true
end

if _G.DecompilerRuntimeContext == nil then
    _G.DecompilerRuntimeContext = true
end

local API_URL = "https://api.luacid.dev/decompile"
local KEY_URL = "https://luacid.dev/getkey"
local MAX_RETRIES = 3

local CONTEXT_MAGIC = "LUACCTX1"
local CONTEXT_CONTENT_TYPE = "application/vnd.luacid.decompile-context; version=1"
local BYTECODE_CONTENT_TYPE = "application/octet-stream"
local MAX_CONTEXT_BYTES = 16 * 1024
local MAX_CONTEXT_ENTRIES = 64
local MAX_CONTEXT_PARENTS = 16
local MAX_CONTEXT_NAME_BYTES = 128
local MAX_CONTEXT_PATH_BYTES = 512

local responseCache = {}

local function errorMessage(title, detail)
    local text = tostring(detail or "unknown error"):gsub("\r\n?", "\n")
    return "-- " .. title .. "\n-- " .. text:gsub("\n", "\n-- ")
end

local function buildUrl()
    local fields = {}
    if type(_G.DecompilerOptions) ~= "table" then
        return API_URL
    end
    for name, value in pairs(_G.DecompilerOptions) do
        fields[#fields + 1] = HttpService:UrlEncode(tostring(name))
            .. "="
            .. HttpService:UrlEncode(tostring(value))
    end
    if #fields == 0 then
        return API_URL
    end
    return API_URL .. "?" .. table.concat(fields, "&")
end

local function contextString(value, maxBytes)
    return if type(value) == "string" and #value > 0 and #value <= maxBytes then value else nil
end

local function instanceReference(value)
    local className = contextString(value.ClassName, MAX_CONTEXT_NAME_BYTES)
    local path = contextString(value:GetFullName(), MAX_CONTEXT_PATH_BYTES)
    if not className or not path then
        return nil
    end
    return className, path
end

local function runtimeReference(value)
    if type(value) ~= "userdata" then
        return nil
    end

    local valueType = typeof(value)
    if valueType == "Instance" then
        local className, path = instanceReference(value)
        if className then
            return { kind = "instance", class = className, path = path }
        end
    elseif valueType == "EnumItem" then
        local enumName = contextString(string.match(tostring(value.EnumType), "^Enum%.(.+)$"), MAX_CONTEXT_NAME_BYTES)
        if enumName then
            return { kind = "enum", name = enumName }
        end
    elseif valueType ~= "userdata" and contextString(valueType, MAX_CONTEXT_NAME_BYTES) then
        return { kind = "datatype", name = valueType }
    end

    return nil
end

local function buildRuntimeInfo(src, bytecode)
    local scriptOk, scriptClass, scriptPath = pcall(instanceReference, src)
    if not scriptOk or not scriptClass or not scriptPath then
        return nil
    end

    local parents = {}
    local parentOk, parent = pcall(function()
        return src.Parent
    end)

    while parentOk and parent and #parents < MAX_CONTEXT_PARENTS do
        local entryOk, parentName, parentClass, nextParent = pcall(function()
            return parent.Name, parent.ClassName, parent.Parent
        end)
        parentName = contextString(parentName, MAX_CONTEXT_NAME_BYTES)
        parentClass = contextString(parentClass, MAX_CONTEXT_NAME_BYTES)
        if not entryOk or not parentName or not parentClass then
            break
        end
        parents[#parents + 1] = { name = parentName, class = parentClass }
        parent = nextParent
    end

    local globals = {}
    if type(getsenv) == "function" then
        local environmentOk, environment = pcall(getsenv, src)
        if environmentOk and type(environment) == "table" then
            for name, value in pairs(environment) do
                local safeName = contextString(name, MAX_CONTEXT_NAME_BYTES)
                local referenceOk, reference = pcall(runtimeReference, value)
                if safeName and referenceOk and reference then
                    globals[#globals + 1] = { name = safeName, reference = reference }
                end
            end
        end
    end

    table.sort(globals, function(left, right)
        return left.name < right.name
    end)

    while #globals > MAX_CONTEXT_ENTRIES do
        globals[#globals] = nil
    end

    local context = {
        version = if #parents > 0 then 2 else 1,
        script = {
            class = scriptClass,
            path = scriptPath,
            parents = if #parents > 0 then parents else nil,
        },
        globals = globals,
    }

    local json = HttpService:JSONEncode(context)

    while #json > MAX_CONTEXT_BYTES and #globals > 0 do
        globals[#globals] = nil
        json = HttpService:JSONEncode(context)
    end

    while #json > MAX_CONTEXT_BYTES and #parents > 0 do
        parents[#parents] = nil
        if #parents == 0 then
            context.version = 1
            context.script.parents = nil
        end
        json = HttpService:JSONEncode(context)
    end

    if #json > MAX_CONTEXT_BYTES then
        return nil
    end
    return CONTEXT_MAGIC .. string.pack("<I4", #json) .. json .. bytecode
end

getgenv().decompile = function(src)
    local ok, bytecode = pcall(getscriptbytecode, src)
    if not ok then
        return errorMessage("Failed to read script bytecode", bytecode)
    end

    local url = buildUrl()
    local hasKey = _G.DecompilerKey and _G.DecompilerKey ~= ""

    local body = bytecode
    local contentType = BYTECODE_CONTENT_TYPE

    if _G.DecompilerRuntimeContext then
        local infoOk, info = pcall(buildRuntimeInfo, src, bytecode)
        if infoOk and info then
            body = info
            contentType = CONTEXT_CONTENT_TYPE
        end
    end

    local cacheKey = url .. "\0" .. body
    local cached = responseCache[cacheKey]

    if cached then
        return cached
    end

    local headers = {
        ["Content-Type"] = contentType,
    }

    if hasKey then
        headers.Authorization = "Bearer " .. _G.DecompilerKey
    end

    if _G.DecompilerTelemetry then
        local executorOk, name, version = pcall(identifyexecutor)
        headers["X-Luacid-Executor"] = if executorOk and name then `{name} {version or ""}` else "unknown"
        headers["X-Luacid-PlaceId"] = string.format("%d", game.PlaceId)
        headers["X-Luacid-GameId"] = string.format("%d", game.GameId)
    end

    local waited = 0

    for attempt = 0, MAX_RETRIES do
        local sent, response = pcall(request, {
            Url = url,
            Method = "POST",
            Headers = headers,
            Body = body,
        })

        local status = sent and response and response.StatusCode

        if status == 200 then
            local source = tostring(response.Body)
            responseCache[cacheKey] = source
            if waited > 0 and not hasKey then
                return string.format("-- Rate limited: %.0fs spent waiting. Key raises your limits: %s\n\n", waited, KEY_URL) .. source
            end
            return source
        end

        local retryable = not status or status == 429 or status >= 500
        if attempt == MAX_RETRIES or not retryable then
            return errorMessage("Decompiler API request failed", if status then `HTTP {status}\n{tostring(response.Body)}` else response)
        end

        local responseHeaders = response and response.Headers or {}
        local delay = tonumber(responseHeaders["Retry-After"]) or 2 ^ attempt
        if status == 429 then
            waited += delay
        end

        warn(string.format("[Luacid] Request failed; retrying in %.1f seconds", delay))
        task.wait(delay)
    end

    return errorMessage("Decompiler API request failed", "unknown error")
end