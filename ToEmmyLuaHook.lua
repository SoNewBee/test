--
-- Copyright (c) 2008-2020 the Urho3D project.
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.

--[[

Generates a .lua file that can be used as a library in sumneko's lua plugin for vscode ( https://github.com/sumneko/lua-language-server )

*** For generating a new Urho3D emmylua library file ***

[Prerequisite]
- CMake 2.8+;
- Compatible compiler for Urho3D (see their Readme file);
- Doxygen (Added in your PATH)

[Process]
- Get the desired version on "http://github.com/urho3d/Urho3D" and "Download Zip";
- Extract and build it with the "-DURHO3D_LUA=1" or "-DURHO3D_LUAJIT=1" and "-DURHO3D_DOCS=1";
- When done, insinuating that you're in the downloaded folder:
- go to Source/Urho3D/LuaScript/pkgs/
- place this file in the pkgs folder
- run tolua++:
	<path/to/build-tree>/bin/tool/tolua++ -L ToEmmyLuaHook.lua -P -o <path/to/build-tree>/Docs/generated/urho3d_emmylua.lua <path/to/build-tree>/Docs/generated/LuaPkgToDox.txt
  (Change slashes side for Windows)
- The API file will be in the Docs/generated folder, named "urho3d_emmylua.lua".
- The file can then be added as a library in the plugin settings
  
  [Credits]
  - edited from Danny Boisvert's "ToZerobraneStudioHook"

--]]

require "ToDoxHook"

local luaCodeBlocks = {}

function classCode:print(ident, close)
  table.insert(luaCodeBlocks, self.text)
end

function printFunction(self, ident, close, isfunc)
  local func = {}
  func.mod   = self.mod
  func.type  = self.type
  func.ptr   = self.ptr
  func.name  = self.name
  func.lname = self.lname
  func.const = self.const
  func.cname = self.cname
  func.lname = self.lname

  if isfunc then
    func.name = func.lname
  end

  currentFunction = func
  local i = 1
  while self.args[i] do
    self.args[i]:print(ident .. "  ", ",")
    i = i + 1
  end
  currentFunction = nil

  if currentClass == nil then
    table.insert(globalFunctions, func)
  else
    if func.name == "new" then
      -- add construct function
      local ctor = deepCopy(func)
      ctor.name = currentClass.name
      ctor.lname = currentClass.name
      ctor.const = "(GC)"
      if ctor.descriptions == nil then
        ctor.descriptions = { "(GC)" }
      else
        table.insert(ctor.descriptions, "(GC)")
      end

      -- insert function as global, since the function should be called like "class()" and not "class.class()"
      table.insert(globalFunctions, ctor)
    end

    if func.name == "delete" then
      func.type = "void"
    end

    if currentClass.functions == nil then
      currentClass.functions = { func }
    else
      table.insert(currentClass.functions, func)
    end
  end
end

---@param genericData {genericParamName : string}
function writeFunctionParamComments(file, declarations, genericData)
  local count = table.maxn(declarations)
  for i = 1, count do
    local declaration = declarations[i]
    if declaration.type ~= "void" then

      local cleanedType = declaration.type:gsub("const ", ""):gsub(".*Vector<([^%*&]*)[%*&]?>", "%1[]")

      local convertedType = ConvertTypeToLuaFallbackIfNeeded(cleanedType)

      local convertedName = ConvertKeywordIfNeeded(declaration.name)

      if genericData then
        if convertedName == genericData.genericParamName then
          convertedType = "`T`"
        end
      end

      local line = "---@param " .. convertedName .. " " .. convertedType

      if declaration.def ~= "" then
        -- param has default value, so we mark it as optional
        line = line .. "?"
      end

      -- add extra info on the param
      if declaration.ptr ~= "" or declaration.def ~= "" or cleanedType ~= convertedType then
        line = line .. " @"
      end

      -- add comment about lua fallback replacement (only add the comment if there won't be another one about pointer/ref)
      if cleanedType ~= convertedType and declaration.ptr == "" then
        line = line .. declaration.type
      end

      -- add comment about pointer or reference indication
      if declaration.ptr ~= "" then
        line = line .. declaration.type .. declaration.ptr
        line = line:gsub("([<>])", "\\%1")
      end

      -- add comment about default value
      if declaration.def ~= "" then
        line = line .. " default value is " .. declaration.def
      end

      file:write(line .. "\n")
    end
  end
end

function writeFunctionArgs(file, declarations)
  local count = table.maxn(declarations)
  for i = 1, count do
    local declaration = declarations[i]
    if declaration.type ~= "void" then
      -- add parameter name
      local convertedName = ConvertKeywordIfNeeded(declaration.name)
      file:write(convertedName)
    end
    if i ~= count then
      file:write(", ")
    end
  end
end

---@param genericData {genericParamName : string, genericParamType : string, overrideReturnType: boolean }
function writeFunctionReturnComment(file, func, genericData)
  if func.type == "void" then return end

  local return_str = "---@return "
  if func.type ~= "" then

    local cleanedType = func.type:gsub("const ", ""):gsub(".*Vector<([^%*&]*)[%*&]?>", "%1[]")
    local convertedType = ConvertTypeToLuaFallbackIfNeeded(cleanedType)

    if genericData then
      if convertedType == genericData.genericParamType or genericData.overrideReturnType then
        convertedType = "T"
      end
    end

    return_str = return_str .. convertedType

    if func.type:find("const") ~= nil or func.type:find(".*Vector<") then
      return_str = return_str .. " @" .. func.type:gsub("([<>])", "\\%1")
    elseif cleanedType ~= convertedType then
      return_str = return_str .. " @" .. func.type
    end


  end

  if func.ptr ~= "" then
    if func.type == "" and classname ~= nil then
      return_str = return_str .. classname
      -- returns pointer comment
      return_str = return_str .. " @" .. classname .. func.ptr
    end
  end

  file:write(return_str .. "\n")
end

function writeInheritances(file, classname)
  for i, inheritance in ipairs(classes) do
    if inheritance.name == classname then
      if inheritance.functions ~= nil then
        for j, func in ipairs(inheritance.functions) do
          writeFunction(file, func, classname, true)
        end
      end
      if inheritance.properties ~= nil then
        for j, property in ipairs(inheritance.properties) do
          writeProperty(file, property, classname)
        end
      end
      -- append inheritance functions & properties
      if inheritance.base ~= "" then
        writeInheritances(file, inheritance.base)
      end
    end
  end
end

function writeClasses(file)
  sortByName(classes)
  -- adjustClassesOverloadFuncs()

  file:write("\n\n  -- Classes\n")
  for _, class in ipairs(classes) do

    local emmyComment = "\n\n---@class " .. class.name
    if class.base ~= "" then
      emmyComment = emmyComment .. " : " .. class.base
    end
    file:write(emmyComment)


    if class.properties ~= nil then
      for i, property in ipairs(class.properties) do
        writeProperty(file, property, class.name)
      end
    end

    if class.functions ~= nil then
      for _, func in ipairs(class.functions) do
        if func.name:find("operator.+") ~= nil then
          writeOperator(file, func, class.name)
        end
      end
    end

    file:write("\n" .. class.name .. " = {}\n")

    if class.functions ~= nil then
      for _, func in ipairs(class.functions) do
        writeFunction(file, func, class.name)
      end
    end

    -- -- append inheritance functions & properties
    -- if class.base ~= "" then
    --   writeInheritances(file, class.base)
    -- end

    file:write("\n")
  end
end

function writeEnumerates(file)
  sortByName(enumerates)
  file:write("\n\n  -- Enumerations\n")

  for _, enumerate in ipairs(enumerates) do
    file:write("\n---@alias " .. enumerate.name .. "\n")
    for _, value in ipairs(enumerate.values) do
      file:write("---| `" .. value .. "`\n")
    end
    -- then write the values again, to stop the analyzer from complaining that the options don't exist
    file:write("\n")
    for _, value in ipairs(enumerate.values) do
      file:write("--- (Readonly) int for enum '" .. enumerate.name .. "'\n")
      file:write("---@type " .. enumerate.name .. "\n")
      file:write(value .. " = {}\n")
    end
  end
end

function writeFunction(file, func, classname, isInheritance, asFunc)
  -- ignore class operators, as we handle them elsewhere
  if (classname == nil) or (func.name:find("operator.+") == nil) then

    -- ignore new/delete object if from inheritance
    if not (isInheritance == true and (func.name == classname or func.name == "new" or func.name == "delete")) then

      file:write("\n")

      -- write description/summary
      if func.descriptions ~= nil then
        for _, description in ipairs(func.descriptions) do
          -- local fixedDescription = description:gsub([[(")]], [[\%1]])
          file:write("--- " .. description .. "\n")
        end
      end

      local genericData = nil

      --- special handling for generic component functions we know about
      if func.name == "CreateComponent" or func.name == "GetComponent" or func.name == "GetOrCreateComponent"
          or func.name == "GetParentComponent" or func.name == "GetComponents" then
        -- make sure it's one of the functions we're thinking about.
        -- they should have "type" as one of the params
        for _, entry in ipairs(func.declarations) do
          if entry.name == "type" then
            genericData = { genericParamName = "type", genericParamType = "Component" }
            break
          end
        end
      elseif func.name == "GetResource" then
        for _, entry in ipairs(func.declarations) do
          if entry.name == "type" then
            genericData = { genericParamName = "type", genericParamType = "Resource" }
            break
          end
        end
      elseif func.name == "GetScriptObject" or func.name == "CreateScriptObject" then
        for _, entry in ipairs(func.declarations) do
          if entry.name == "scriptObjectType" then
            genericData = { genericParamName = "scriptObjectType", genericParamType = "LuaScriptObject", overrideReturnType = true}
            break
          end
        end
      elseif classname == "UIElement" and func.name == "CreateChild" then
        for _, entry in ipairs(func.declarations) do
          if entry.name == "type" then
            genericData = { genericParamName = "type", genericParamType = "UIElement"}
            break
          end
        end
      end

      if genericData then
        file:write("---@generic T : " .. genericData.genericParamType .. "\n")
      end

      writeFunctionParamComments(file, func.declarations, genericData)
      writeFunctionReturnComment(file, func, genericData)


      -- write function begin
      file:write("function ")
      if classname ~= nil then
        if asFunc == true then
          file:write(classname .. "." .. func.name) -- accepts auto-completion with ".", ":" and global
        else
          file:write(classname .. ":" .. func.name) -- accepts auto-completion only with ":"
        end
      else
        -- global function
        file:write(func.name)
      end


      -- write parameters
      file:write("(")
      if func.declarations ~= nil then
        writeFunctionArgs(file, func.declarations)
      end
      file:write(") end\n")

      -- write overloaded functions
      if func.overloads ~= nil then
        for i, overload in ipairs(func.overloads) do
          writeFunction(file, overload, classname, isInheritance, asFunc)
        end
      end

      file:write("\n")
    end
  end
end


function writeOperator(file, func, classname, isInheritance, asFunc)

  local description = ""
  local operationType = ""
  local rhsType = ""
  local resultType = ""

  -- description/summary
  if func.descriptions ~= nil then
    for _, desc in ipairs(func.descriptions) do
      -- local fixedDescription = description:gsub([[(")]], [[\%1]])
      description = description .. desc
    end
  end

  -- params
  for _, declaration in ipairs(func.declarations) do
    if declaration.type ~= "void" then

      local cleanedType = declaration.type:gsub("const ", ""):gsub(".*Vector<([^%*&]*)[%*&]?>", "%1[]")

      rhsType = ConvertTypeToLuaFallbackIfNeeded(cleanedType)

      -- add comment about lua fallback replacement (only add the comment if there won't be another one about pointer/ref)
      if cleanedType ~= rhsType and declaration.ptr == "" then
        description = description .. " " .. declaration.type
      end

      -- add comment about pointer or reference indication
      if declaration.ptr ~= "" then
        local ptrComment = declaration.type .. declaration.ptr
        ptrComment = ptrComment:gsub("([<>])", "\\%1")
        description = description .. " " .. ptrComment
      end

    end
  end

  -- return value
  if func.type ~= "void" then
    if func.type ~= "" then

      local cleanedType = func.type:gsub("const ", ""):gsub(".*Vector<([^%*&]*)[%*&]?>", "%1[]")
      resultType = ConvertTypeToLuaFallbackIfNeeded(cleanedType)


      if func.type:find("const") ~= nil or func.type:find(".*Vector<") then
        description = description .. " return: " .. func.type:gsub("([<>])", "\\%1")
      elseif cleanedType ~= resultType then
        description = description .. " return: " .. func.type
      end

    end

    if func.ptr ~= "" then
      if func.type == "" and classname ~= nil then
        description = description .. " return: " .. classname .. func.ptr
      end
    end
  end

  -- actual operator
  local operatorSign = func.name:gsub("operator", "")

  if operatorSign == "+" then
    operationType = "add"
  elseif operatorSign == "==" then
    return -- this operator doesn't seem to be supported by the lua plugin yet
    --operationType = "eq"
  elseif operatorSign == "*" then
    operationType = "mul"
  elseif operatorSign == "/" then
    operationType = "div"
  elseif operatorSign == "-" then
    if rhsType ~= "" then
      operationType = "sub"
    else
      operationType = "unm"
    end
  elseif operatorSign == "<" then
    return -- this operator doesn't seem to be supported by the lua plugin yet
    -- operationType = "lt"
  elseif operatorSign == "[]" or operatorSign == "&[]" then
    return -- this operator doesn't seem to be supported by the lua plugin yet
    -- operationType = "index"
  elseif operatorSign == "bool" then
    return -- not sure about this one
  else
    operationType = operatorSign
  end

  file:write("\n---@operator " .. operationType)

  if rhsType ~= "" then
    file:write("(" .. rhsType .. ")")
  end

  if resultType ~= "" then
    file:write(": " .. resultType)
  end

  if description ~= "" then
    file:write(" @" .. description)
  end

  -- write overloaded operator functions
  if func.overloads ~= nil then
    for i, overload in ipairs(func.overloads) do
      writeOperator(file, overload, classname, isInheritance, asFunc)
    end
  end

end

function writeGlobalConstants(file)
  sortByName(globalConstants)

  file:write("\n\n  -- Global Constants\n")
  for i, constant in ipairs(globalConstants) do
    file:write('\n---@type ' ..
      ConvertTypeToLuaFallbackIfNeeded(constant.type:gsub("(const%s+)", "")) ..
      " @ " .. constant.type .. constant.ptr .. "\n")
    file:write(constant.name .. " = nil\n")
  end
end

function writeGlobalFunctions(file)
  sortByName(globalFunctions)

  file:write("\n\n  -- Global Functions\n")
  for i, func in ipairs(globalFunctions) do
    writeFunction(file, func, nil, nil, true)
  end
end

function writeGlobalProperties(file)
  file:write("\n")
  for i, property in ipairs(globalProperties) do
    writeProperty(file, property)
  end
end

function writeProperty(file, property, classname)

  local isReadonly = property.mod:find("tolua_readonly") ~= nil
  local cleanedType = property.type:gsub("(const%s+)", ""):gsub(".*Vector<([^%*&]*)[%*&]?>", "%1[]")
  local convertedType = ConvertTypeToLuaFallbackIfNeeded(cleanedType)
  local originalTypeComment = ""
  local adjustedDescriptions = ""

  if isReadonly then
    adjustedDescriptions = adjustedDescriptions .. "(Readonly) "
  end

  -- get description(s)
  if property.descriptions ~= nil then
    for i, description in ipairs(property.descriptions) do
      local adjustedDescription = description:gsub([[(")]], [[\%1]])
      adjustedDescriptions = adjustedDescriptions .. " " .. adjustedDescription
    end
  end

  -- add extra description if we've removed parts or replaced the type
  if property.type:find(".*Vector<") ~= nil or property.type:find("(const%s+)") then
    originalTypeComment = " original type: " .. property.type:gsub("([<>])", "\\%1")
  elseif cleanedType ~= convertedType then
    originalTypeComment = " original type: " .. property.type
  end

  -- the structure is different if this is a class field. if it is, it should be written right after the @class declaration
  if classname ~= "" and classname ~= nil then
    file:write("\n---@field " .. property.name .. " " .. convertedType)

    if adjustedDescriptions ~= "" then
      file:write(" " .. adjustedDescriptions)
    end

    if originalTypeComment ~= "" then
      file:write(" " .. originalTypeComment)
    end
  else
    -- write description (type) comment. Not needed if this isn't a pointer or anything else "special"
    if not isReadonly then
      if property.ptr ~= "" then
        file:write("\n--- " .. property.type .. property.ptr)
      end
    else
      file:write("\n--- (Readonly) " .. property.type:gsub("([<>])", "\\%1") .. property.ptr)
    end

    if adjustedDescriptions ~= "" then
      file:write("\n--- " .. adjustedDescriptions)
    end

    if originalTypeComment ~= "" then
      file:write("\n--- " .. originalTypeComment)
    end

    -- write valuetype
    if property.type ~= "" then
      file:write("\n---@type " .. convertedType)
    end

    file:write("\n" .. property.name .. " = nil\n")
  end

end

function writeLuaCodeBlocks(file)

  file:write("\n-- Lua Code from pkg files\n\n")

  for _, code in ipairs(luaCodeBlocks) do
    -- add some emmylua comments manually where we know they should be
    code = code:gsub("(LuaScriptObject = {})",
      "---@class LuaScriptObject\n---@field instance LuaScriptObject\n---@field Remove fun(self:LuaScriptObject)\n%1\n\n---@type Node\nLuaScriptObject.node = {}")
    code = code:gsub("(function LuaScriptObject:GetNode())", "---@return Node\n%1")
    code = code:gsub("(function ScriptObject())", "---@return LuaScriptObject\n%1")
    file:write(code .. "\n")
  end
end

-- function writeCommonTypesTranslations(file)

--   file:write("\n-- extra class declarations for common types\n\n")

--   function writeTypeTranslation(file, providedType, translatedType)
--     local translation = "---@class " .. providedType .. " : " .. translatedType .. "\n"
--     translation = translation .. providedType .. " = {}"
--     file:write(translation .. "\n")
--   end

--   writeTypeTranslation(file, "bool", "boolean")
--   writeTypeTranslation(file, "int", "integer")
--   writeTypeTranslation(file, "short", "integer")
--   writeTypeTranslation(file, "long", "integer")
--   writeTypeTranslation(file, "unsigned", "integer")
--   writeTypeTranslation(file, "float", "number")
--   writeTypeTranslation(file, "double", "number")
--   writeTypeTranslation(file, "String", "string")
--   writeTypeTranslation(file, "char", "string")

-- end


--- checks if the type matches one of our fallback types, returning the matched type; returns the unchanged type otherwise
function ConvertTypeToLuaFallbackIfNeeded(type)

  if type == "String" or type == "char" or type == "char*" then
    return "string"
  elseif type == "String[]" or type == "StringVector" then
    return "string[]"
  elseif type == "int" or type == "unsigned" or type == "short" or type == "long" then
    return "integer"
  elseif type == "int[]" or type == "unsigned[]" or type == "short[]" or type == "long[]" then
    return "integer[]"
  elseif type == "float" or type == "double" then
    return "number"
  elseif type == "bool" then
    return "boolean"
  elseif type == "void*" then
    return "any"
  elseif type == "Urho3D::Context" then
    return "Context"
  end

  return type

end

--- returns a word similar to the one provided if it is a lua keyword. If it isn't, returns the same word
function ConvertKeywordIfNeeded(word)

  if word == "end" then
    return "End"
  elseif word == "repeat" then
    return "Repeat"
  end

  return word

end

function classPackage:print()
  curDir = getCurrentDirectory()

  if flags.o == nil then
    print("Invalid output filename");
    return
  end

  local filename = flags.o
  local file = io.open(filename, "wt")

  file:write("---@meta\n\n") -- mark file as library file

  file:write("-- Urho3D emmylua API generated on " .. os.date('%Y-%m-%d'))
  file:write("\n\n")

  local i = 1
  while self[i] do
    self[i]:print("", "")
    i = i + 1
  end
  printDescriptionsFromPackageFile(flags.f)

  -- writeCommonTypesTranslations(file)
  writeLuaCodeBlocks(file)
  writeClasses(file)
  writeEnumerates(file)
  writeGlobalFunctions(file)
  writeGlobalProperties(file)
  writeGlobalConstants(file)

  file:close()
end
