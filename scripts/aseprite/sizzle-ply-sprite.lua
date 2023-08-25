--
-- Create a layered sprite, compatible with the CraftMicro SDK
--

-- There must be a sprite
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
dlg:combobox{ id="output", label="Output", option="JSON condensed", options={ "JSON verbose", "JSON condensed" } } -- "Jx"
dlg:combobox{ id="optimise", label="Optimise", option="Rotations only", options={ "Rotations and Flips", "Rotations only" } }
dlg:combobox{ id="layers", label="Layers", option="Visible only", options={ "Visible only", "All layers" } }
dlg:button{ id="continue", text="Continue" }
dlg:show()

outputAsJx = dlg.data.output == "Jx"
outputVerbose = dlg.data.output == "JSON verbose"
supportFlips = dlg.data.optimise == "Rotations and Flips"
allLayers = dlg.data.layers == "All layers"

-- Number of pixels across all parts
local partsArea = 0

-- Output
output = {
    width = sprite.width,
    height = sprite.height,
    parts = {},
    animations = {}
}

-- Slugify a string
slugify = function(str)
    return string.gsub(string.gsub(string.lower(str),"[^ a-z0-9]",""),"[ ]+","-")
end

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

-- Ensure colormode is RGB
if origColorMode ~= ColorMode.RGB then
    app.command.ChangePixelFormat{ format="rgb" }
end

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
    print("Processing "..tag.name)
    animation = {name = tag.name, direction = tag.aniDir, frames = {}}
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
                                print("Warning! Anchor shape not correct for '"..tag.name.."' on frame "..frame.frameNumber)
                            end
                            if gotAnchor then
                                print("Anchor for '"..tag.name.."' set to "..anchor.x..","..anchor.y.." on frame "..frame.frameNumber)
                            end
                        else
                            print("Warning! Anchor not drawn at correct size (3x3) for '"..tag.name.."' on frame "..frame.frameNumber)
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
-- Prepare output data files
--
local outputId = slugify(app.fs.fileTitle(sprite.filename))
local outputName = app.fs.joinPath(app.fs.filePath(sprite.filename), outputId)

--
-- Image tile
--

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
        print("Trying larger buffer. Failed at "..(buffer * 100).."%")
        buffer = buffer + 0.05
    end
end
imageCropped = Image(cropx, cropy)
imageCropped:drawImage(image, Point(0,0))
print("Final image size "..cropx.."x"..cropy)

-- Save the image tile
imageCropped:saveAs(outputName..".png")
print("Save image tile to '"..outputId..".png'")

--
-- Write output data
--

-- Prepare
table.sort(output.parts, function (p1, p2) return p1.index < p2.index end)
for _, p in pairs(output.parts) do
    p.index = nil
    p.image = nil
    p.name = nil
end
output.image = outputId..".png"

-- Output format
if outputVerbose then
    -- Verbose
    local namedAnims = {}
    for _, a in pairs(output.animations) do
        namedAnims[a.name] = a;
        namedAnims[a.name].name = nil
    end
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
        local anim = {a.name, a.direction, {a.anchor.x, a.anchor.y}}
        local frames = {}
        for _, f in pairs(a.frames) do
            local frame = {f.duration}
            local parts = {}
            for _, p in pairs(f.parts) do
                table.insert(parts, {p.index, p.orientation, p.x, p.y})
            end
            table.insert(frame, parts)
            table.insert(frames, frame)
        end
        table.insert(anim, frames)
        print("Inserting "..a.name)
        table.insert(anims, anim)
    end
    table.insert(condensedOutput, anims)
    output = condensedOutput;
end

-- Save
local json = dofile("./json.lua")
local file = io.open(outputName..".json", "w")
file:write(json.encode(output))
file:close()
print("Save data file to '"..outputId..".json'")

-- Reset color mode
if origColorMode == ColorMode.INDEXED then
    app.command.ChangePixelFormat{ format="indexed", dithering="none" }
elseif origColorMode == ColorMode.GRAY then
    app.command.ChangePixelFormat{ format="gray" }
end
