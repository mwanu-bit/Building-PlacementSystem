--Desc:Script handles a building system similar to the one in games such as Work At a Pizza Place
--The system handles teh following features: Core Building Logic such as Placement of Build,Rotation of Builds to be Placed and Destruction of Placed Builds
--The system is a combination of what would have been two scripts a handler and class scripts
------[[MODULE]]-----
local BuildingHandler = {}
BuildingHandler.__index = BuildingHandler

-----[[SERVICES]]-----
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")

local Players = game:GetService("Players")
local Player = Players.LocalPlayer

------[[VARIABLES]]-----
--/Ui
local MainGui = Player:WaitForChild("PlayerGui"):WaitForChild("MainGui")
local BuildFrame = MainGui:WaitForChild("BuildFrame")

local ItemsFrame = BuildFrame:WaitForChild("ItemsFrame")
local TemplateButton = ReplicatedStorage.Assets.UiTemplates.TemplateButton

local DestroyButton :ImageButton = BuildFrame:WaitForChild("DestroyButton")

local Mouse = Player:GetMouse()
local Camera = workspace.CurrentCamera

----[[DATA]]-----
--We store build model data into the table below we do this so that we may be able to display the Model's Image and also display what type of placement is it -- More on That explained below
local BuildModelsData = {
    ["Table"] = {
        ID = 82808060712703;
        PlacementType = "Ground" 
    };
    
    ["DefaultPart"] = {
        ID = 108065504504500;
        PlacementType = "Any"
    };
    
    ["Chair"] = {
        ID = 94073954725613;
        PlacementType = "Ground"
    };
    
    ["House"] = {
        ID = 124600264363488;
        PlacementType = "Ground"
    }
}

--These are placement types for the models we do this to ensure that certain models such as for example a table model can't be placed on another tabler model
local PlacementTypes = {
    ["Any"] = {"Any","Ground"}; --If a surface is tagged "any" you can only place builds that are either tageed "ground" or any
    ["Ground"] = {"Any"} --If a surface is tagged "ground" you can only place surfaces tagged "any" on it
}


--//BuildParts
local BuildModels = ReplicatedStorage.Assets.BuildParts

--//Modules
--Packages
local Trove = require(ReplicatedStorage.Modules.SharedModules.Packages.Trove)
local Fusion = require(ReplicatedStorage.Modules.SharedModules.Packages.Fusion)

local BuildObjects = {}
local Children = Fusion.Children

local CurrentBuildObject = nil

--//Destroy mode vars
local DestroyModeOn = false -- Stores if "true" if the player clicked the destroy button and the destroy mode was set to false
local InstanceToDestroy = nil -- Stores any instnace hit by the ray cast in destroy mode

local DestroyModeTrove = Trove.new()

------[[FUNCTIONS]]-----
--Helper functions
local function GetModel(HitInstance)
    --We use this function to return the model the players mouse is currently hovering over so we can do several things such as maybe destroy it
    local Model = HitInstance:FindFirstAncestorOfClass("Model")
    if not Model then
        return HitInstance
    end

    local NewModel = HitInstance:FindFirstAncestorOfClass("Model")
    return GetModel(NewModel)

end

--Class Creation
function BuildingHandler.new(Build,PlacementType:string)
    local self = setmetatable({},BuildingHandler)
    
    self._trove = Trove.new() -- We use this trove to clean up the whole object and any of its connections and parts attached to it such as a model if the model/part is destroyed
    self.Build = self._trove:Add(Build:Clone())
  
    self.isBuilding = false
    self.canPlace = false
    
    self.HitInstance = nil
    self._ghostTrove = self._trove:Add(Trove.new()) -- We create a trove for cleaning up ghost builds/models which are used to show where the player will place the current build/Model they are trying to create
 
    self.PlacementType = PlacementType
    self.RotationAngle = 0
    return self
    
end

--This function is called when the player click a button for a build/model and wants to possobly start building it
function BuildingHandler:On_Build()
    --Sanity Check
    if self.isBuilding then
        return
    end  
    
    -- the destroy mode was previously on we turn it off
    if DestroyModeOn then
        DestroyModeOn = false
        DestroyModeTrove:Clean()          
    end
    
    CurrentBuildObject = self
    self.isBuilding = true

    --We start by creating a "ghost" of the model/Part the player is going to build this will act as an indicator to where the player will actually place that part/model or if they can actually place it
    -- All of the "ghost" models/Parts are stored in a ghost trove which is cleaned up once the player stops building so we avoid causing memory leaks
    self._ghostBuild = self._ghostTrove:Add(self.Build:Clone())
    for _,Part in self._ghostBuild:GetDescendants() do
        if Part:IsA("BasePart") then
            Part.CanCollide = false
            Part.Transparency = 0.45
        end
    end
    
    self._ghostBuild.Parent = workspace:WaitForChild("GhostBuilds")

    --We create a hitbox to cover the whole area of the part/model in order to detect if the player is trying to place the part/model inside other builds, hence preventing that
    local cFrame,Size = self.Build:GetBoundingBox()
    self._hitBox = self._ghostTrove:Add(Instance.new("Part"))
    self._hitBox.CanCollide = false

    self._hitBox.CFrame = cFrame
  
    self._hitBox.Size = Size
    self._hitBox.Transparency = 0.8
    
    self._hitBox.Anchored = true
    self._hitBox.Parent = workspace:WaitForChild("HitBoxes")
    
    --raycast Params
    local RayCastParams = RaycastParams.new()
    RayCastParams.FilterType = Enum.RaycastFilterType.Exclude
    RayCastParams.FilterDescendantsInstances = {Player.Character or Player.CharacterAdded:Wait(),self._ghostBuild,self._hitBox}

    --We use a runservice connection to consistenetly update the model/parts CFrame and orientation to wherever the raycast from the player last hit
    self._ghostTrove:Connect(RunService.RenderStepped,function(dt)
        --Theray fires from the players screen position to thier mouse position/their last touch position
        local MouseRay = Camera:ScreenPointToRay(Mouse.X,Mouse.Y)   
        local Direction = MouseRay.Direction * 500
        
        local Origin = MouseRay.Origin
        local RayResult = workspace:Raycast(Origin,Direction,RayCastParams)
        
        if RayResult then
            self.HitInstance = RayResult.Instance
            local HitPosition = RayResult.Position
           
            local halfHeight = self._hitBox.Size.Y/2
            local finalPosition = HitPosition + Vector3.new(0,halfHeight,0) -- we add half height so that the ghostmodel/part is placed above the instance hit

            local rotationCF = CFrame.Angles(0,math.rad(self.RotationAngle),0)
            local FinalCFrame = CFrame.new(finalPosition) * rotationCF
            
            
            self._ghostBuild:PivotTo(FinalCFrame)
            self._hitBox.CFrame = FinalCFrame

        end
        
        self:_handleHitbox()
    end)
    
    local function PlaceBuild(actionName,InputState,InputObject)
        self:Place_Build(actionName,InputState,InputObject)
    end
    
    local function RotateBuild(actionName,InputState,InputObject)
        self:Rotate_Build(actionName,InputState,InputObject)
    end

    --We bind the action for actually placing the model/part to the players touch if on mobile or thier mouse click
    ContextActionService:BindAction("Build",PlaceBuild,false,Enum.UserInputType.MouseButton1,Enum.UserInputType.Touch)

    --We also bind another action which is the key press R to rotate the Model 90 degrees on The Z axis so to give the player alot more control on how they are going to be placing the buil/model
    ContextActionService:BindAction("Rotate",RotateBuild,false,Enum.KeyCode.R)
  
end

--Functions rotates the current Build object on the Z axis by 90 degress so to give the player a lot more control on how they want theier "build" to look like
function BuildingHandler:Rotate_Build(actionName,InputState,InputObject)
    if actionName ~= "Rotate" or InputState ~= Enum.UserInputState.Begin then
        return
    end
    
    self.RotationAngle += 90
end

--Function handles the Hitbox every frame
function BuildingHandler:_handleHitbox()
    if not self._hitBox or not self.HitInstance  then
        return
    end
    
    local PartParams = OverlapParams.new()
    PartParams.MaxParts = 50
    PartParams.FilterType = Enum.RaycastFilterType.Exclude
    PartParams.FilterDescendantsInstances = {Player.Character or Player.CharacterAdded:Wait(),self._ghostBuild,self._hitBox}

    --We get the parts within the hitbox so to check if they are otehr builds hence restricting the player from actually placing theier current model/part
    local Parts = workspace:GetPartsInPart(self._hitBox,PartParams)
    if #Parts >= 1 then        
        self._hitBox.Color = Color3.new(1, 0.0588235, 0.2)
        self.canPlace = false
        return
    end
   
    --We also get the  "placementType" of what the model the phit box is within to also check if the player can place the current build/part on that specific placement type
    local HitInstancePlacementType = nil
    if self.HitInstance.Name == "Hitbox" and self.HitInstance.Parent:IsA("Model") then
        HitInstancePlacementType = self.HitInstance.Parent:GetAttribute("PlacementType")
        
    else
        local HitInstance = self.HitInstance
        HitInstance = GetModel(HitInstance)
        
        local Hitbox = HitInstance:FindFirstChild("Hitbox")
        if Hitbox then
            HitInstancePlacementType = Hitbox.Parent:GetAttribute("PlacementType")
        end
        
    end

    --Fall back if none is found we just do "Any"
    if not HitInstancePlacementType then
        HitInstancePlacementType = "Any"
    end
    
    self.HitInstancePlacementType = HitInstancePlacementType

    --We change the hitbox's colour based on the factors above such as placementype and what the hitbox is over lapping with to give actual visual feed back to the player to whether they can place the model/part
    local CanPlace = table.find(PlacementTypes[HitInstancePlacementType],self.PlacementType)
    if not CanPlace then
        --if they can'r place the hitbox's colour is set to red 
        self._hitBox.Color = Color3.new(1, 0.0588235, 0.2)
        self.canPlace = false
        return
    end

    --if they can place it the hotbox's colour is set to green
    self._hitBox.Color = Color3.new(0.333333, 1, 0)
    self.canPlace = true
    
end

--Function handles placing the current build/model and calling a clean up function to the ghost trove of that model/part to avoid any memory leaks
function BuildingHandler:Place_Build(actionName,InputState,InputObject)
    --Sanity Checks
    if InputState ~= Enum.UserInputState.Begin then
        return
    end
    
    if not self.canPlace  or not InputObject or not self.HitInstance then
        return
    end
    
    self.canPlace = false
    
    local PlacementType = nil
    if self.HitInstancePlacementType ~= "Any" then
        PlacementType = self.HitInstancePlacementType
    else
        PlacementType = self.PlacementType
    end
    
    --If a surface was tagged "ground" and the part you place is tagged "any" then the parts  placement type will change to ground
    --We do this to ensure certain parts/models can't be stacked onto one another
    local Build = self._ghostBuild:Clone()
    Build:SetAttribute("PlacementType",PlacementType)

    for _,Part in Build:GetDescendants() do
        if Part:IsA("BasePart") then
            Part.CanCollide = true
            Part.Transparency = 0
        end
    end
    
    Build.Parent = workspace

    --We clone a new hitbox for the model,part placed and parent it to that specific model/part so if to detect what models/parts in the game the player can actually destroy
    local HitBoxClone = self._hitBox:Clone()    
    HitBoxClone.Transparency = 1
   
    HitBoxClone.Name = "Hitbox"
    HitBoxClone.Parent = Build
end

--Function fires when the player finished building this mainly fires if the button for the specific model/part is activated again or if the destroy mode is activated
function BuildingHandler:Finish_Build()
    --Sanity Check
    if not self.isBuilding then
        return
    end

    --We reset all the variables in the object
    self.isBuilding = false  
    self.canPlace = false
    
    self._ghostTrove:Clean()  
    self.HitInstance = nil

    --We unbind the actions 
    ContextActionService:UnbindAction("Build")
    ContextActionService:UnbindAction("Rotate")
    
    CurrentBuildObject = nil
end 

--Function is used to destroy a model and its object completely
function BuildingHandler:Destroy()
    self._trove:Destroy
end    

--function is called when turning off the detsroy mode to disconnect all connectons and unbind certain actions set
function BuildingHandler.Cleanup_DestroyMode()
    --Sanity check
    if not DestroyModeOn then
        return
    end
    DestroyModeOn = false   -- We set the destroy mode back to false
    --We do clean ups to prevent memory leaks
    ContextActionService:UnbindAction("DestroyInstance")
    
    InstanceToDestroy = nil
    DestroyModeTrove:Clean()
end

--Function to set up the ui for the player to be able to access diffrent models/parts to actually build/destroy
--
function BuildingHandler._SetUpUi()
    --Function sets up the 
    local function SetUpBuildObject(Model:Model,PlacementType)
        local BuildObject = BuildingHandler.new(Model,PlacementType)
        BuildObjects[Model.Name] = BuildObject
        
        return BuildObject
    end
    
    --Function detsroy the hitinstance if the destroyaction is bound
    local function DestroyInstance(actionName,InputState,InputObject)
        if InputState ~= Enum.UserInputState.Begin or actionName ~= "DestroyInstance" then
            return
        end
        
        if not InstanceToDestroy then
            return
        end
        
        InstanceToDestroy:Destroy()
    end

    --We set up a new button every entry inside the buildModelsData
    for ModelName,ModelInfo in BuildModelsData do
        local Model = BuildModels:FindFirstChild(ModelName)
        if not Model then
            continue
        end
        
        
        local Scope = {
            New = Fusion.New,
            Value = Fusion.Value
        }
        
        local Button = Scope:New "ImageButton" {
            Name = ModelName,
            Image = "rbxassetid://".. ModelInfo.ID,
            BackgroundTransparency = 1,
            Parent = ItemsFrame,
            [Children] = {
                Scope:New "UICorner" {
                    CornerRadius = UDim.new(0,8)
                }
            }
        }

        --We connect an activated even to eitehr activate build mode/finish build mdoe for that specific buil it also stops the build mode of another model/part if itw as active
        Button.Activated:Connect(function()

            --We get a build object for that button representig a model/part
            local BuildObject
            if BuildObjects[ModelName] then
                BuildObject = BuildObjects[ModelName]
            
            else
                    --we create one just in case none exists
                BuildObject = SetUpBuildObject(Model,ModelInfo.PlacementType)
            end

            --If another build object was currently active we stop it 
            if CurrentBuildObject and CurrentBuildObject ~= BuildObject then
                CurrentBuildObject:Finish_Build()
            end

            --if this build object was currently active we also stop it then return -- Its a way the player stops the build mode of a specifc part/model
            if BuildObject.isBuilding then
                BuildObject:Finish_Build()
                return
            end

            --We start building if all the checks passed
            BuildObject:On_Build(ModelName)
        end)
        
    end

    --We set up the logic of the detsroy button this includes activating/deactivating it and also showing a red selection box around the model/partw e are going to detsroy but only if
    --the model/part had a htbox suggesting that the player placed it so players can't detroy one anotehrs models/parts
    DestroyButton.Activated:Connect(function()

            --If a build obejct is currently runningw e stop it
        if CurrentBuildObject then
            CurrentBuildObject:Finish_Build()
        end

        --The function checks if the detsroy mode is on if it is it cleans it up and deacrivates the detsroy mode
        BuildingHandler.Cleanup_DestroyMode()

        --we find a selection box stored iside the players "mainGui"
        local SelectionBox :SelectionBox = MainGui:FindFirstChildOfClass("SelectionBox")
        if not SelectionBox then
            -- if the selection box doesn't exist we create one and add it to the detsroy mode trove for future clean up
            SelectionBox = DestroyModeTrove:Add(Instance.new("SelectionBox"))
            SelectionBox.Color3 = Color3.new(1, 0, 0)
            
            SelectionBox.Parent = MainGui
        end
        
        DestroyModeOn = true    
        --We conect a renderstepped connection to constantly shoot out a ray form the player camera to their current mouse/touch position to get if anything that the player built previously was hit to add a selcion box to it
        DestroyModeTrove:Connect(RunService.RenderStepped,function(dt)
            --The ray fires from the players camera to thier mouse position
            local MouseRay = Camera:ScreenPointToRay(Mouse.X,Mouse.Y)   
            local Direction = MouseRay.Direction * 100

            local Origin = MouseRay.Origin
            local RayResult = workspace:Raycast(Origin,Direction)
            
            if not RayResult then
                InstanceToDestroy = nil
                SelectionBox.Adornee = nil
                return
            end
            
            local HitInstance = RayResult.Instance
            local HitboxInstance = nil
            
            local Model = GetModel(HitInstance)
          
            local Hitbox = Model:FindFirstChild("Hitbox")         
            if Hitbox then
                HitboxInstance = Hitbox
            end
           
            --If not hitbox instance was hit then remove selection box
            if not HitboxInstance then
                InstanceToDestroy = nil
                SelectionBox.Adornee = nil
                return
            end
            
            InstanceToDestroy = Model      
            SelectionBox.Adornee = Model
        end)
        
        -- We bind the input for destroying
        ContextActionService:BindAction("DestroyInstance",DestroyInstance,false,Enum.UserInputType.Touch,Enum.UserInputType.MouseButton1)
       
    end)
end
    
--Initializes the module    
function BuildingHandler.Init()
    BuildingHandler._SetUpUi()
    
end

return BuildingHandler

