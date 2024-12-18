--
-- Script to create a ply-sprite from Aseprite
-- Requires Aseprite v1.3rc6 or higher
--
-- Supported by:
--   Sizzle (dart, multi-platform)
--   CraftMicro SDK (c++, microcontrollers)
--
-- Usage (first time):
--   1) Open Aseprite
--   2) Go to File > Scripts > Open scripts folder
--   3) Copy this file to the scripts folder
--   4) In Aseprite, go to File > Scripts > Rescan scripts folder
--   5) Run the script: File > Scripts > ply-sprite
--
-- Usage:
--   1) File > Scripts > ply-sprite
--
local sprite = app.activeSprite
if sprite == nil then
    return app.alert("ERROR: There is no active sprite")
end
local origColorMode = sprite.colorMode
if origColorMode == ColorMode.TILE then
    return app.alert("ERROR: Tilemaps are not supported")
end

-- Dialog for options
local dlg = Dialog()
dlg:entry{ id="name", label="Name", text=app.fs.fileTitle(sprite.filename) }
dlg:combobox{ id="output", label="Output", option="Sizzle", options={ "Sizzle", "Sizzle - debug", "CraftMicro SDK" } }
dlg:combobox{ id="layers", label="Layers", option="Visible only", options={ "Visible only", "All layers" } }
dlg:button{ id="continue", text="Continue" }
dlg:show()

local outputCppHeader = dlg.data.output == "CraftMicro SDK"
local outputJson = not outputCppHeader
local outputImage = not outputCppHeader
local outputVerbose = dlg.data.output == "Sizzle - debug"
local supportFlips = dlg.data.output == "CraftMicro SDK"
local allLayers = dlg.data.layers == "All layers"
local outputBaseName = dlg.data.name

-- Ensure colormode is correct
if outputCppHeader then
    if origColorMode ~= ColorMode.INDEXED then
        app.command.ChangePixelFormat{ format="indexed", dithering="none" }
    end
else
    if origColorMode ~= ColorMode.RGB then
        app.command.ChangePixelFormat{ format="rgb" }
    end
end

-- Slugify a string
slugify = function(str, sep)
    return string.gsub(string.gsub(string.gsub(string.lower(str),"[-_]",sep),"[^ a-z0-9-_]",""),"[ ]+",sep)
end

-- Output names
local outputId = slugify(outputBaseName, "-")
local outputName = app.fs.joinPath(app.fs.filePath(sprite.filename), outputId)

-- Number of pixels across all parts
local partsArea = 0

-- Output
local output = {
    width = sprite.width,
    height = sprite.height,
    parts = {},
    animations = {}
}

-- Function to compare images
ImageCompare = {
    Different = -1,
    Same = 0,
    FlipH = 1,
    FlipV = 2,
    Rot90 = 4,
}
pixelFromIndex = function(index, image)
    local y = math.floor(index/image.width)
    local x = index - y * image.width
    return image:getPixel(x, y)
end
compareImagePixels = function(source, dest, destStart, destStep, destStride)
    local total = source.width * source.height
    local steps = source.width
    local sourcePos = 0
    local destPos = destStart
    while total > 0 do
        if pixelFromIndex(sourcePos, source) ~= pixelFromIndex(destPos, dest) then
            return false
        end
        steps = steps - 1
        sourcePos = sourcePos + 1
        destPos = destPos + destStep
        if steps == 0 then
            steps = source.width
            destStart = destStart + destStride
            destPos = destStart
        end
        total = total - 1
    end
    return true
end
compareImages = function(part, compare)
    -- Check if image is right-side or possibly rotated based on size
    local checkNonRotated = false
    local checkRotated = false
    if part.image.width == compare.width and part.image.height == compare.height then 
        checkNonRotated = true
        if compare.width == compare.height then
            checkRotated = true
        end
    elseif part.image.width == compare.height and part.image.height == compare.width then 
        -- rotated
        checkRotated = true
    else
        return ImageCompare.Different;
    end

    -- Check right-side first
    if checkNonRotated then
        if compareImagePixels(part.image, compare, 0, 1, compare.width) then
            return ImageCompare.Same
        end
        if supportFlips and compareImagePixels(part.image, compare, compare.width-1, -1, compare.width) then
            return ImageCompare.FlipH
        end
        if supportFlips and compareImagePixels(part.image, compare, compare.width*(compare.height-1), 1, -compare.width) then
            return ImageCompare.FlipV
        end
        if compareImagePixels(part.image, compare, compare.width*compare.height-1, -1, -compare.width) then
            return ImageCompare.FlipH | ImageCompare.FlipV --Rot180
        end
    end
    -- Check rotated second
    if checkRotated then
        if compareImagePixels(part.image, compare, compare.width-1, compare.width, -1) then
            return ImageCompare.Rot90
        end
        if supportFlips and compareImagePixels(part.image, compare, 0, compare.width, 1) then
            return ImageCompare.Rot90 | ImageCompare.FlipH
        end
        if supportFlips and compareImagePixels(part.image, compare, compare.width*compare.height-1, -compare.width, -1) then
            return ImageCompare.Rot90 | ImageCompare.FlipV
        end
        if compareImagePixels(part.image, compare, compare.width*(compare.height-1), -compare.width, 1) then
            return ImageCompare.Rot90 | ImageCompare.FlipH | ImageCompare.FlipV --Rot270
        end
    end

    return ImageCompare.Different;
end

--
-- Step through all animations
--
-- If there are no tags, just one animation will be created of the entire sprite
-- If there are tags, parts of the sprite with no tag will be skipped. So either
-- ensure that you use tags for all animations, or no tags at all!

print("Creating PlySprite files for "..outputId);

-- Default tag if none are set
local tags = sprite.tags
if #tags == 0 then
    tags = {{
        name = "sprite",
        aniDir = AniDir.FORWARD,
        fromFrame = sprite.frames[1],
        toFrame = sprite.frames[#sprite.frames]
    }}
end

-- Step tags (animations)
for _,tag in ipairs(tags) do
    print("  Processing animation "..tag.name)
    animation = {name = tag.name, direction = tag.aniDir, repeats = tag.repeats, frames = {}}
    local gotAnchor = false
    local anchor = {x=0, y=0}

    frame = tag.fromFrame
    while frame do
        layeredSprite = {duration = frame.duration, parts = {}}

        -- Step through all layers
        for _,layer in ipairs(sprite.layers) do

            -- Anchor
            if layer.name == "_anchor" then
                if not gotAnchor then
                    local cel = layer:cel(frame.frameNumber)
                    if cel ~= nil then
                        if cel.image.width == 3 and cel.image.height == 3 then
                            if cel.image:getPixel(0,0) & 0xff000000 == 0 then
                                anchor = {x=cel.bounds.x + 3, y=cel.bounds.y + 3}
                                gotAnchor = true
                            elseif cel.image:getPixel(2,0) & 0xff000000 == 0 then
                                anchor = {x=cel.bounds.x, y=cel.bounds.y + 3}
                                gotAnchor = true
                            elseif cel.image:getPixel(0,2) & 0xff000000 == 0 then
                                anchor = {x=cel.bounds.x + 3, y=cel.bounds.y}
                                gotAnchor = true
                            elseif cel.image:getPixel(2,2) & 0xff000000 == 0 then
                                anchor = {x=cel.bounds.x, y=cel.bounds.y}
                                gotAnchor = true
                            else
                                print("    Warning! Anchor shape not correct for '"..tag.name.."' on frame "..frame.frameNumber)
                            end
                            if gotAnchor then
                                print("    Anchor set to "..anchor.x..","..anchor.y.." on frame "..frame.frameNumber)
                            end
                        else
                            print("    Warning! Anchor not drawn at correct size (3x3) for '"..tag.name.."' on frame "..frame.frameNumber)
                        end
                    end
                end
                goto next_layer
            end
            
            -- Ignore invisible layers
            if not allLayers and not layer.isVisible then
                goto next_layer
            end

            -- Get the cell
            local cel = layer:cel(frame.frameNumber)
            if cel == nil then
                goto next_layer
            end
            local bounds = cel.bounds

            -- Check against all parts to see if duplicate
            local part = nil
            local orientation = ImageCompare.Different
            for _, p in pairs(output.parts) do
                orientation = compareImages(p, cel.image)
                if orientation ~= ImageCompare.Different then
                    part = p
                    break
                end
            end

            if part == nil then
                -- Insert into parts
                part = {
                    index = #output.parts,
                    name = layer.name.."_"..frame.frameNumber,
                    image = cel.image
                }
                --print("      Inserting part {"..part.index..", "..part.name..", "..part.image.width.."x"..part.image.height.."}")
                table.insert(output.parts, part)
                partsArea = partsArea + cel.image.width * cel.image.height
                orientation = ImageCompare.Same
            end

            -- Add to layered sprite
            local sharedPart = {
                index = part.index,
                x = bounds.x,
                y = bounds.y,
                orientation = orientation,
                blendmode = layer.blendMode,
                alpha = layer.opacity,
            }
            table.insert(layeredSprite.parts, sharedPart)

            ::next_layer::
        end

        -- Add layered sprite to table
        table.insert(animation.frames, layeredSprite)

        -- Next frame
        frame = frame.next
        if frame and frame.frameNumber > tag.toFrame.frameNumber then
            frame = nil
        end
    end

    animation.anchor = anchor;
    table.insert(output.animations, animation)
end

--
-- Image tile
--
if outputImage then

    print("  Creating image");

    -- Estimate final size (add 5% buffer to start)
    sortParts = function(p1, p2)
        if p1.image.height == p2.image.height then
            return p1.image.width > p2.image.width
        else
            return p1.image.height > p2.image.height
        end
    end
    table.sort(output.parts, sortParts)

    local buffer = 0.05
    local image = nil
    local placed = false
    local cropx = 0
    local cropy = 0
    while not placed do
        sideLength = math.ceil(math.sqrt(partsArea * (1 + buffer)))
        image = Image(sideLength, sideLength)
        imageRows = {}
        for i=0, sideLength do
            imageRows[i] = 0
        end
        for _, p in pairs(output.parts) do
            placed = false
            for y=0, sideLength - p.image.height do
                for x=0, sideLength - p.image.width do
                    if imageRows[y] <= x then
                        image:drawImage(p.image, Point(x,y))
                        p.x = x
                        p.y = y
                        p.width = p.image.width
                        p.height = p.image.height
                        for i=0, p.image.height - 1 do
                            imageRows[y + i] = x + p.image.width
                        end
                        cropx = math.max(cropx, x + p.image.width)
                        cropy = math.max(cropy, y + p.image.height)
                        placed = true
                        break
                    end
                end
                if placed then break end
            end
            if not placed then break end
        end
        if not placed then
            buffer = buffer + 0.05
        end
    end
    imageCropped = Image(cropx, cropy)
    imageCropped:drawImage(image, Point(0,0))
    print("    Final image size "..cropx.."x"..cropy.." (buffer "..(buffer * 100).."%)")

    -- Save the image tile
    imageCropped:saveAs(outputName..".png")
    print("    Save image tile to '"..outputId..".png'")
end -- outputImage

--
-- Write output data
--

table.sort(output.parts, function (p1, p2) return p1.index < p2.index end)

--
-- header JSON
-- 
if outputJson then

    -- Prepare
    for _, p in pairs(output.parts) do
        p.index = nil
        p.image = nil
        p.name = nil
    end

    -- output format
    if outputVerbose then
        -- Verbose
        local namedAnims = {}
        for _, a in pairs(output.animations) do
            namedAnims[a.name] = a;
            namedAnims[a.name].name = nil
        end
        output.image = outputId..".png"
        output.animations = namedAnims
    else
        -- Condensed
        local condensedOutput = {{output.width, output.height}}
        local parts = {}
        for _, p in pairs(output.parts) do
            table.insert(parts, {p.x, p.y, p.width, p.height})
        end
        table.insert(condensedOutput, parts)
        local anims = {}
        for _, a in pairs(output.animations) do
            local anim = {a.name, a.direction, a.repeats, {a.anchor.x, a.anchor.y}}
            local frames = {}
            for _, f in pairs(a.frames) do
                local frame = {f.duration}
                local parts = {}
                for _, p in pairs(f.parts) do
                    table.insert(parts, {p.index, p.orientation, p.x, p.y, p.alpha, p.blendmode})
                end
                table.insert(frame, parts)
                table.insert(frames, frame)
            end
            table.insert(anim, frames)
            table.insert(anims, anim)
        end
        table.insert(condensedOutput, anims)
        output = condensedOutput;
    end

    -- Save
    local file = io.open(outputName..".json", "w")
    file:write(json.encode(output))
    file:close()
    print("  Save data file to '"..outputId..".json'")

end -- outputJson

--
-- output c++ header
--
if outputCppHeader then
    calcPartIndexData = function(part, orientation)
        if orientation == 0 then
            return {
                start = 0,
                strideX = 1,
                strideY = part.image.width
            }
        end
        if orientation == (ImageCompare.FlipH) then
            return {
                start = part.image.width-1,
                strideX = -1,
                strideY = part.image.width
            }
        end
        if orientation == (ImageCompare.FlipV) then
            return {
                start = part.image.width*(part.image.height-1),
                strideX = 1,
                strideY = -part.image.width
            }
        end
        if orientation == (ImageCompare.FlipH | ImageCompare.FlipV) then
            return {
                start = part.image.width*part.image.height-1,
                strideX = -1,
                strideY = -part.image.width
            }
        end
        if orientation == (ImageCompare.Rot90) then
            return {
                start = part.image.width*(part.image.height-1),
                strideX = -part.image.width,
                strideY = 1
            }
        end
        if orientation == (ImageCompare.Rot90 | ImageCompare.FlipH) then
            return {
                start = 0,
                strideX = part.image.width,
                strideY = 1
            }
        end
        if orientation == (ImageCompare.Rot90 | ImageCompare.FlipV) then
            return {
                start = part.image.width*part.image.height-1,
                strideX = -part.image.width,
                strideY = -1
            }
        end
        if orientation == (ImageCompare.Rot90 | ImageCompare.FlipH | ImageCompare.FlipV) then
            return {
                start = part.image.width - 1,
                strideX = part.image.width,
                strideY = -1
            }
        end
    end

    animDirectionEnum = function(index)
        if index == 1 then
            return "AnimationDirection::Reverse"
        elseif index == 2 then
            return "AnimationDirection::PingPong"
        elseif index == 3 then
            return "AnimationDirection::PongPing"
        end
        return "AnimationDirection::Forward"
    end
    
    animOrientationEnum = function(index)
        if index == 0 then
            return "Transform::None"
        end
        local s = {}
        if (index & 1) ~= 0 then
            table.insert(s, "Transform::FlipH")
        end
        if (index & 2) ~= 0 then
            table.insert(s, "Transform::FlipV")
        end
        if (index & 4) ~= 0 then
            table.insert(s, "Transform::Rotate90")
        end
        if #s == 0 then
            table.insert(s, "Transform::None")
        end
        return table.concat(s, " | ")
    end

    -- prepare header
    local outputIdCpp = slugify(outputBaseName, "_")
    local outputNameCpp = app.fs.joinPath(app.fs.filePath(sprite.filename), outputIdCpp)
    local header = "#pragma once\n\n#include \"display/Sprite.h\"\n\nusing namespace craft;\n\n"

    --
    -- Palette
    --
    -- TODO: Support non-indexed sprites by building a palette, including
    -- matching/combining close colors (choose most frequently used match). 

    local palette = sprite.palettes[1]
    header = header.."// Palette ("..#palette.." entries)\n"
    header = header.."static const uint32_t "..outputIdCpp.."_palette[] = {\n"
    for i=0,#palette-1 do
        local c = palette:getColor(i)
        if i > 0 then
            header = header..",\n"
        end
        header = header.."\t0x"..string.format("%02x", c.alpha)..string.format("%02x", c.red)..string.format("%02x", c.green)..string.format("%02x", c.blue)
    end
    header = header.."\n};\n\n"

    -- Parts

    for _, p in pairs(output.parts) do
        local count = 0
        local total = p.image.width * p.image.height
        header = header.."// "..p.name.." ("..total.." bytes)\n"
        header = header.."static const uint8_t "..outputIdCpp.."_part"..p.index.."_data[] = {\n"
        for y = 0, p.image.height-1 do
            for x = 0, p.image.width-1 do
                px = p.image:getPixel(x, y)
                if count % 16 == 0 then
                    header = header.."\t"
                end
                header = header.."0x"..string.format("%02x", px)
                count = count + 1
                if count < total then
                    header = header..","
                end
                if count % 16 == 0 then
                    header = header.."\n"
                end
            end
        end
        if count % 16 ~= 0 then
            header = header.."\n"
        end
        header = header.."};\n"
    end

    header = header.."\n// Parts array ("..#output.parts.." parts)\n"
    header = header.."static const PlySpritePart "..outputIdCpp.."_parts[] = {\n"
    for _, p in pairs(output.parts) do
        header = header.."\t{\n"
        header = header.."\t\t.width = "..p.image.width..",\n"
        header = header.."\t\t.height = "..p.image.height..",\n"
        header = header.."\t\t.anchorX = 0,\n"
        header = header.."\t\t.anchorY = 0,\n"
        header = header.."\t\t.partData = "..outputIdCpp.."_part"..p.index.."_data\n"
        header = header.."\t}"
        if p.index < #output.parts then
            header = header..","
        end
        header = header.."\n"
    end
    header = header.."};\n\n"

    local animIndex = 0
    for _, a in pairs(output.animations) do
        local frameIndex = 0
        for _, f in ipairs(a.frames) do
            header = header.."\n// Animation '"..a.name.."' frame "..frameIndex.." layers ("..#f.parts.." layers)\n"
            header = header.."static const PlySpriteLayer "..outputIdCpp.."_anim"..animIndex.."_layer"..frameIndex.."_data[] = {\n"
            local count = 0
            for _, p in pairs(f.parts) do
                local partIndexData = calcPartIndexData(output.parts[p.index + 1], p.orientation)
                header = header.."\t{\n"
                header = header.."\t\t.partIndex = "..p.index..",\n"
                header = header.."\t\t.orientation = "..animOrientationEnum(p.orientation)..",\n"
                header = header.."\t\t.x = "..p.x..",\n"
                header = header.."\t\t.y = "..p.y..",\n"
                header = header.."\t\t.start = "..partIndexData.start..",\n"
                header = header.."\t\t.strideX = "..partIndexData.strideX..",\n"
                header = header.."\t\t.strideY = "..partIndexData.strideY.."\n"
                header = header.."\t}"
                count = count + 1
                if count < #f.parts then
                    header = header..","
                end
                header = header.."\n"
            end
            header = header.."};\n\n"
            frameIndex = frameIndex + 1
        end

        header = header.."\n// Animation '"..a.name.."' frames array ("..#a.frames.." frames)\n"
        header = header.."static const PlySpriteFrame "..outputIdCpp.."_anim"..animIndex.."_frames[] = {\n"
        local count = 0
        local frameIndex = 0
        for _, f in pairs(a.frames) do
            header = header.."\t{\n"
            header = header.."\t\t.duration = "..string.format("%.4f", f.duration)..",\n"
            header = header.."\t\t.layerCount = "..#f.parts..",\n"
            header = header.."\t\t.layerData = "..outputIdCpp.."_anim"..animIndex.."_layer"..frameIndex.."_data\n"
            header = header.."\t}"
            count = count + 1
            if count < #a.frames then
                header = header..","
            end
            header = header.."\n"
            frameIndex = frameIndex + 1
        end
        header = header.."};\n\n"
        animIndex = animIndex + 1
    end
    local animCount = animIndex

    header = header.."// Animations array\n"
    header = header.."static const PlySpriteAnim "..outputIdCpp.."_anims[] = {\n"
    local animIndex = 0
    local total = 0
    for _, a in pairs(output.animations) do
        total = total + #a.name + 1
        header = header.."\t// Animation '"..a.name.."'\n"
        header = header.."\t{\n"
        header = header.."\t\t.direction = "..animDirectionEnum(a.direction)..",\n"
        header = header.."\t\t.repeats = "..a.repeats..",\n"
        header = header.."\t\t.anchorX = "..math.floor(a.anchor.x + 0.5)..",\n"
        header = header.."\t\t.anchorY = "..math.floor(a.anchor.y + 0.5)..",\n"
        header = header.."\t\t.frameCount = "..#a.frames..",\n"
        header = header.."\t\t.frameData = "..outputIdCpp.."_anim"..animIndex.."_frames\n"
        header = header.."\t}"
        if (animIndex < #output.animations) then
            header = header..","
        end
        animIndex = animIndex + 1
        header = header.."\n"
    end
    header = header.."};\n\n"

    header = header.."// Animation names\n"
    header = header.."static const int8_t "..outputIdCpp.."_names[] = {\n"
    local count = 0
    for _, a in pairs(output.animations) do
        if count % 16 == 0 then
            header = header.."\t"
        end
        header = header.."0x"..string.format("%02x", #a.name)
        count = count + 1
        if count < total then
            header = header..","
        end
        if count % 16 == 0 then
            header = header.."\n"
        end

        for c in a.name:gmatch"." do
            if count % 16 == 0 then
                header = header.."\t"
            end
            header = header.."0x"..string.format("%02x", (string.byte(c)))
            count = count + 1
            if count < total then
                header = header..","
            end
            if count % 16 == 0 then
                header = header.."\n"
            end
        end
    end
    if count % 16 ~= 0 then
        header = header.."\n"
    end
    header = header.."};\n\n"

    --
    -- Sprite data
    --

    header = header.."// Ply sprite\n"
    header = header.."static const PlySpriteData "..outputIdCpp.." = {\n"
    header = header.."\t.paletteCount = "..#palette..",\n"
    header = header.."\t.paletteData = "..outputIdCpp.."_palette,\n"
    header = header.."\t.partCount = "..#output.parts..",\n"
    header = header.."\t.partData = "..outputIdCpp.."_parts,\n"
    header = header.."\t.animCount = "..animCount..",\n"
    header = header.."\t.animData = "..outputIdCpp.."_anims,\n"
    header = header.."\t.animNames = "..outputIdCpp.."_names,\n"
    header = header.."\t.width = "..sprite.width..",\n"
    header = header.."\t.height = "..sprite.height.."\n"
    header = header.."};\n\n"

    local file = io.open(outputNameCpp..".h", "w")
    file:write(header)
    file:close()
    print("Save header file to '"..outputIdCpp..".h'")
end -- outputCppHeader

-- Reset color mode
if origColorMode == ColorMode.INDEXED then
    if sprite.colorMode ~= ColorMode.INDEXED then
        app.command.ChangePixelFormat{ format="indexed", dithering="none" }
    end
elseif origColorMode == ColorMode.GRAY then
    if sprite.colorMode ~= ColorMode.GRAY then
        app.command.ChangePixelFormat{ format="gray" }
    end
elseif origColorMode == ColorMode.RGB then
    if sprite.colorMode ~= ColorMode.RGB then
        app.command.ChangePixelFormat{ format="rgb" }
    end
end
