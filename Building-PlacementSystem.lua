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

local PlacementTypes = {
    ["Any"] = {"Any","Ground"}; --If a surface is tagged any you can only place builds that are either tageed ground or any
    ["Ground"] = {"Any"} --If a surface is tagged ground you can only place surfaces tagged any on it
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
local DestroyModeOn = false
local InstanceToDestroy = nil -- Stores any instnace hit by the ray cast in destroy mode

local DestroyModeTrove = Trove.new()

------[[FUNCTIONS]]-----
--Helper functions
local function GetModel(HitInstance)

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
    
    self._trove = Trove.new()
    self.Build = self._trove:Add(Build:Clone())
  
    self.isBuilding = false
    self.canPlace = false
    
    self.HitInstance = nil
    self._ghostTrove = self._trove:Add(Trove.new()) -- Stores the part for the ghost
 
    self.PlacementType = PlacementType
    self.RotationAngle = 0
    return self
    
end

--Function enables the player to start building
function BuildingHandler:On_Build()
    --Sanity Check
    if self.isBuilding then
        return
    end  
    
    -- the detsroy mode was previosuly on we turn it off
    if DestroyModeOn then
        DestroyModeOn = false
        DestroyModeTrove:Clean()          
    end
    
    CurrentBuildObject = self
    self.isBuilding = true
    
    self._ghostBuild = self._ghostTrove:Add(self.Build:Clone())
    for _,Part in self._ghostBuild:GetDescendants() do
        if Part:IsA("BasePart") then
            Part.CanCollide = false
            Part.Transparency = 0.45
        end
    end
    
    self._ghostBuild.Parent = workspace:WaitForChild("GhostBuilds")

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
    
    self._ghostTrove:Connect(RunService.RenderStepped,function(dt)
        
        local MouseRay = Camera:ScreenPointToRay(Mouse.X,Mouse.Y)   
        local Direction = MouseRay.Direction * 500
        
        local Origin = MouseRay.Origin
        local RayResult = workspace:Raycast(Origin,Direction,RayCastParams)
        
        if RayResult then
            self.HitInstance = RayResult.Instance
            local HitPosition = RayResult.Position
           
            local halfHeight = self._hitBox.Size.Y/2
            local finalPosition = HitPosition + Vector3.new(0,halfHeight,0)

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
    
    ContextActionService:BindAction("Build",PlaceBuild,false,Enum.UserInputType.MouseButton1,Enum.UserInputType.Touch)
    ContextActionService:BindAction("Rotate",RotateBuild,false,Enum.KeyCode.R)
  
    --Runservice Conn
end

--Functions rotates the current Build object on the Z axis
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
    
    local Parts = workspace:GetPartsInPart(self._hitBox,PartParams)
    if #Parts >= 1 then
        
        self._hitBox.Color = Color3.new(1, 0.0588235, 0.2)
        self.canPlace = false
        return
    end
   
 
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
    
    if not HitInstancePlacementType then
        HitInstancePlacementType = "Any"
    end
    
    self.HitInstancePlacementType = HitInstancePlacementType

    local CanPlace = table.find(PlacementTypes[HitInstancePlacementType],self.PlacementType)
    if not CanPlace then
        self._hitBox.Color = Color3.new(1, 0.0588235, 0.2)
        self.canPlace = false
        return
    end
    
    self._hitBox.Color = Color3.new(0.333333, 1, 0)
    self.canPlace = true
    
end

--Function handles placing the building
function BuildingHandler:Place_Build(actionName,InputState,InputObject)
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
    local Build = self._ghostBuild:Clone()
    Build:SetAttribute("PlacementType",PlacementType)

    for _,Part in Build:GetDescendants() do
        if Part:IsA("BasePart") then
            Part.CanCollide = true
            Part.Transparency = 0
        end
    end
    
    Build.Parent = workspace
    local HitBoxClone = self._hitBox:Clone()
    
    HitBoxClone.Transparency = 1
   
    HitBoxClone.Name = "Hitbox"
    HitBoxClone.Parent = Build
    
    --self:Finish_Build()
end

--Function fires when the player finished building
function BuildingHandler:Finish_Build()
    --Sanity Check
    if not self.isBuilding then
        return
    end
   
    self.isBuilding = false  
    self.canPlace = false
    
    self._ghostTrove:Clean()  
    self.HitInstance = nil
    
    ContextActionService:UnbindAction("Build")
    ContextActionService:UnbindAction("Rotate")
    
    CurrentBuildObject = nil
end 

--Function to detsroy an object
function BuildingHandler:DestroyObject()
    self._trove:Destroy()
end

--functions used to celan up teh destroy mode when it gets turned off
function BuildingHandler.Cleanup_DestroyMode()
    if not DestroyModeOn then
        return
    end
    DestroyModeOn = false   
    ContextActionService:UnbindAction("DestroyInstance")
    
    InstanceToDestroy = nil
    DestroyModeTrove:Clean()
end

--Function to set up the ui
function BuildingHandler._SetUpUi()
    
   
    --Function sets up
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
        
        Button.Activated:Connect(function()
        
            local BuildObject
            if BuildObjects[ModelName] then
                BuildObject = BuildObjects[ModelName]
            
            else
                BuildObject = SetUpBuildObject(Model,ModelInfo.PlacementType)
            end
            
            if CurrentBuildObject and CurrentBuildObject ~= BuildObject then
                CurrentBuildObject:Finish_Build()
            end
            
            if BuildObject.isBuilding then
                warn("Build object was building so we finish building")
                BuildObject:Finish_Build()
                return
            end
            
            BuildObject:On_Build(ModelName)
        end)
        
    end
    
    DestroyButton.Activated:Connect(function()
        
        if CurrentBuildObject then
            CurrentBuildObject:Finish_Build()
        end
        
       
        BuildingHandler.Cleanup_DestroyMode()
        
        local SelectionBox :SelectionBox = MainGui:FindFirstChildOfClass("SelectionBox")
        if not SelectionBox then
            SelectionBox = DestroyModeTrove:Add(Instance.new("SelectionBox"))
            SelectionBox.Color3 = Color3.new(1, 0, 0)
            
            SelectionBox.Parent = MainGui
        end
        
        DestroyModeOn = true    
        DestroyModeTrove:Connect(RunService.RenderStepped,function(dt)

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

