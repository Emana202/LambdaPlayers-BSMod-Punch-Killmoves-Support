if !file.Exists( "autorun/bsmod_killmove.lua", "LUA" ) then return end

local allowKillMoves = CreateLambdaConvar( "lambdaplayers_bsmod_enablekillmoves", 1, true, false, false, "If Lambda Players are allowed to execute kill moves from BSMod on their enemies.", 0, 1, { type = "Bool", name = "Enable KillMoves", category = "BSMod KillMoves" } )
local killMovePlayers = CreateLambdaConvar( "lambdaplayers_bsmod_killmoveplayers", 1, true, false, false, "If Lambda Players are allowed to execute kill moves on real players.", 0, 1, { type = "Bool", name = "KillMoves Players", category = "BSMod KillMoves" } )
local killMoveNPCs = CreateLambdaConvar( "lambdaplayers_bsmod_killmovenpcs", 1, true, false, false, "If Lambda Players are allowed to execute kill moves on NPCs.", 0, 1, { type = "Bool", name = "KillMove NPCs", category = "BSMod KillMoves" } )
local dontAttackKillMoveables = CreateLambdaConvar( "lambdaplayers_bsmod_dontattackkillmoveables", 1, true, false, false, "If Lambda Players shouldn't attack with their weapon at a target that can be easily killmoved.", 0, 1, { type = "Bool", name = "Don't Attack KillMoveables", category = "BSMod KillMoves" } )

local IsValid = IsValid
local net = net

if ( CLIENT ) then

    local hook_Run = hook.Run

    net.Receive( "lambdaplayers_bsmod_ragdollhook", function()
        local lambda = net.ReadEntity()
        if !IsValid( lambda ) or !IsValid( lambda.kmviewentity ) or !IsValid( lambda.kmviewanim ) then return end

        local ragdoll = lambda.ragdoll
        if !IsValid( ragdoll ) then return end

        hook_Run( "KMRagdoll", lambda, ragdoll, lambda.kmviewanim:GetSequenceName( lambda.kmviewanim:GetSequence() ) )
    end )

end

if ( SERVER ) then

    util.AddNetworkString( "lambdaplayers_bsmod_ragdollhook" )

    local CurTime = CurTime
    local ipairs = ipairs
    local random = math.random
    local Rand = math.Rand
    local min = math.min
    local SimpleTimer = timer.Simple
    local ents_Create = ents.Create
    local spawnHealthVials = GetConVar( "bsmod_killmove_spawn_healthvial" )
    local spawnHealthKits = GetConVar( "bsmod_killmove_spawn_healthkit" )
    local killMoveMinHP = GetConVar( "bsmod_killmove_minhealth" )
    local killMoveAlways = GetConVar( "bsmod_killmove_anytime" )
    local killMoveBehind = GetConVar( "bsmod_killmove_anytime_behind" )

    local function LambdaKillMove( self, target, animName, plyKMModel, targetKMModel, plyKMPosition, plyKMAngle, plyKMTime, targetKMTime, moveTarget )
        if plyKMModel == "" or targetKMModel == "" or animName == "" then return end
        if self.inKillMove or self:Health() <= 0 or !IsValid( target ) or target.inKillMove or target == self then return end

        --End of return checks
        
        net.Start("debugbsmodcalcview")
        net.Broadcast()
        
        self.inKillMove = true
        
        local tempSelf
        local tempTarget

        --Reverse player and target identifiers if target is set to move instead
        if moveTarget then 
            tempSelf = target
            tempTarget = self
        else
            tempSelf = self
            tempTarget = target
        end

        if plyKMPosition != nil then
            tempSelf:SetPos( plyKMPosition )
        else
            tempSelf:SetPos( tempTarget:GetPos() + ( tempTarget:GetForward() * 40 ) )
        end

        --Set the player to look at the tempTarget by default
        tempSelf:SetAngles( ( Vector( tempTarget:GetPos().x, tempTarget:GetPos().y, 0 ) - Vector( tempSelf:GetPos().x, tempSelf:GetPos().y, 0 ) ):Angle() )
        if tempSelf:IsPlayer() then tempSelf:SetEyeAngles( ( Vector( tempTarget:GetPos().x, tempTarget:GetPos().y, 0 ) - Vector( tempSelf:GetPos().x, tempSelf:GetPos().y, 0 ) ):Angle() ) end
        
        --Override the default angle if a custom one is set
        if plyKMAngle != nil then
            tempSelf:SetAngles( plyKMAngle )
            if tempSelf:IsPlayer() then tempSelf:SetEyeAngles( plyKMAngle ) end
        end
            
        local hiddenChildren = nil
        local prevWeapon = nil
        local prevGodMode = self:HasGodMode()
        local prevMaterial = self:GetMaterial()

        if self:IsPlayer() and IsValid( self:GetActiveWeapon() ) then
            prevWeapon = self:GetActiveWeapon()
        end
        
        if self.killMovable then self:SetKillMovable(false) end

        self:Lock()
        self:SetVelocity( -self:GetVelocity() )
        self:DrawShadow( false )

        if self.IsLambdaPlayer then
            self:ClientSideNoDraw( self, true )
            self:SetNoDraw( true )

            prevWeapon = self.l_Weapon
            self:SwitchWeapon( "none" )
            self:PreventWeaponSwitch( true )

            hiddenChildren = {}
            for _, child in ipairs( self:GetChildren() ) do
                if child == self.WeaponEnt or !IsValid( child ) or child:GetNoDraw() then continue end

                local mdl = child:GetModel()
                if !mdl or mdl == "" then continue end

                self:ClientSideNoDraw( child, true )
                child:SetRenderMode( RENDERMODE_NONE )
                child:DrawShadow( false )
                hiddenChildren[ #hiddenChildren + 1 ] = child
            end

            self:SetCollisionGroup( COLLISION_GROUP_VEHICLE )
            self:GetPhysicsObject():EnableCollisions( false )

            if random( 1, 100 ) <= min( 100, self:GetVoiceChance() * 2 ) then
                local killerLine = ( random( 1, 2 ) == 1 and "kill" or ( random( 1, 2 ) == 1 and "taunt" or "laugh" ) )
                self:SimpleTimer( Rand( 0.2, 1.0 ), function() self:PlaySoundFile( self:GetVoiceLine( killerLine ), true ) end )
            end
        else
            self:SetMaterial( "null" )
        end
     
        net.Start( "removedecals" )
            net.WriteEntity( self )
        net.Broadcast()

        --Spawn the players animation model
        
        if IsValid( self.kmAnim ) then self.kmAnim:Remove() end
        
        self.kmAnim = ents_Create( "ent_km_model" )
        self.kmAnim:SetPos( self:GetPos() )
        self.kmAnim:SetAngles( self:GetAngles() )
        self.kmAnim:SetModel( plyKMModel )
        self.kmAnim:SetOwner( self )
        
        self.kmAnim:ResetSequence( animName )
        self.kmAnim:ResetSequenceInfo()
        self.kmAnim:SetCycle( 0 )
        
        for i = 0, self:GetBoneCount() - 1 do 
            local bone = self.kmAnim:LookupBone( self:GetBoneName( i ) )
            if !bone then continue end
            
            self.kmAnim:ManipulateBonePosition( bone, self:GetManipulateBonePosition( i ) )
            self.kmAnim:ManipulateBoneAngles( bone, self:GetManipulateBoneAngles( i ) )
            self.kmAnim:ManipulateBoneScale( bone, self:GetManipulateBoneScale( i ) )
        end
        
        self.kmAnim:SetModelScale( self:GetModelScale() )
        self.kmAnim:Spawn()
        
        plyKMTime = plyKMTime or self.kmAnim:SequenceDuration()
        
        --Spawn the players model and bonemerge it to the animation model
        
        if IsValid( self.kmModel ) then self.kmModel:Remove() end
        
        self.kmModel = ents_Create( "ent_km_model" )
        self.kmModel:SetPos( self:GetPos() )
        self.kmModel:SetAngles( self:GetAngles() )
        self.kmModel:SetModel( self:GetModel() )
        self.kmModel:SetSkin( self:GetSkin() )
        self.kmModel:SetColor( self:GetColor() )
        self.kmModel:SetMaterial( prevMaterial )
        self.kmModel:SetRenderMode( self:GetRenderMode() )
        self.kmModel:SetOwner( self )

        if self.IsLambdaPlayer then
            for _, child in ipairs( hiddenChildren ) do
                local fakeChild = ents_Create( "base_anim" )
                fakeChild:SetModel( child:GetModel() )
                fakeChild:SetPos( self.kmModel:GetPos() )
                fakeChild:SetAngles( self.kmModel:GetAngles() )
                fakeChild:SetOwner( self.kmModel )
                fakeChild:SetParent( self.kmModel )
                fakeChild:Spawn()
                fakeChild:AddEffects( EF_BONEMERGE )
                self.kmModel:DeleteOnRemove( fakeChild )
            end
        elseif self:IsPlayer() then 
            self:Give("weapon_bsmod_killmove")

            if IsValid( self:GetActiveWeapon() ) then
                self.kmModel.Weapon = self:GetActiveWeapon()

                if self:GetActiveWeapon():GetClass() != "weapon_bsmod_punch" then
                    self:SelectWeapon( "weapon_bsmod_killmove" )
                end
            end
        end

        for _, bodygroup in ipairs( self:GetBodyGroups() ) do
            self.kmModel:SetBodygroup( bodygroup.id, self:GetBodygroup( bodygroup.id ) )
        end
        
        for _, ent in ipairs(self:GetChildren()) do 
            ent:SetParent( self, ent:GetParentAttachment() )
            ent:SetLocalPos( vector_origin )
            ent:SetLocalAngles( angle_zero )
        end 

        self.kmModel.maxKMTime = plyKMTime
        self.kmModel:Spawn()

        self.kmModel:AddEffects( EF_BONEMERGE )
        self.kmModel:SetParent( self.kmAnim )
        
        ------------------------------------------------------------------------------------------
        
        local prevTMaterial = target:GetMaterial()

        target:SetKillMovable( false )
        target.inKillMove = true

        if target:IsPlayer() then
            target:SetMaterial( "null" )
        else
            target:SetNoDraw( true )
        end
        if target.IsLambdaPlayer then
            target:ClientSideNoDraw( target, true )
        end
        target:DrawShadow( false )

        net.Start("removedecals")
            net.WriteEntity(target)
        net.Broadcast()

        if target:IsNPC() then
            target:SetCondition( 67 )
            target:SetNPCState( NPC_STATE_NONE )
        elseif target:IsPlayer() or target.IsLambdaPlayer then
            target:Lock()
            self:SetVelocity(-self:GetVelocity())
        end

        local hiddenChildren2
        if target.IsLambdaPlayer then
            target:SwitchWeapon( "none" )
            target:PreventWeaponSwitch( true )

            hiddenChildren2 = {}
            for _, child in ipairs( target:GetChildren() ) do
                if child == target.WeaponEnt or !IsValid( child ) or child:GetNoDraw() then continue end

                local mdl = child:GetModel()
                if !mdl or mdl == "" then continue end

                target:ClientSideNoDraw( child, true )
                child:SetRenderMode( RENDERMODE_NONE )
                child:DrawShadow( false )
                hiddenChildren2[ #hiddenChildren2 + 1 ] = child
            end

            if random( 1, 100 ) <= min( 100, target:GetVoiceChance() * 2 ) then
                local targetLine = ( random( 1, 3 ) == 1 and "death" or "panic" )
                target:SimpleTimer( Rand( 0.2, 0.8 ), function() target:PlaySoundFile( target:GetVoiceLine( targetLine ), false ) end )
            end
        end

        --Now for the targets animation model

        if IsValid( target.kmAnim ) then target.kmAnim:Remove() end

        target.kmAnim = ents_Create( "ent_km_model" )
        target.kmAnim:SetPos( target:GetPos() )
        target.kmAnim:SetAngles( target:GetAngles() )
        target.kmAnim:SetModel( targetKMModel )
        target.kmAnim:SetOwner( target )

        target.kmAnim:ResetSequence( animName )
        target.kmAnim:ResetSequenceInfo()
        target.kmAnim:SetCycle( 0 )

        for i = 0, target:GetBoneCount() - 1 do 
            local bone = target.kmAnim:LookupBone( target:GetBoneName( i ) )
            if !bone then continue end
            
            target.kmAnim:ManipulateBonePosition( bone, target:GetManipulateBonePosition( i ) )
            target.kmAnim:ManipulateBoneAngles( bone, target:GetManipulateBoneAngles( i ) )
            target.kmAnim:ManipulateBoneScale( bone, target:GetManipulateBoneScale( i ) )
        end

        target.kmAnim:SetModelScale(target:GetModelScale())
        target.kmAnim:Spawn()

        targetKMTime = targetKMTime or target.kmAnim:SequenceDuration()

        --And the targets model

        if IsValid( target.kmModel ) then target.kmModel:Remove() end

        target.kmModel = ents_Create( "ent_km_model" )
        target.kmModel:SetPos( target:GetPos() )
        target.kmModel:SetAngles( target:GetAngles() )
        target.kmModel:SetModel( target:GetModel() )
        target.kmModel:SetSkin( target:GetSkin() )
        target.kmModel:SetColor( target:GetColor() )
        target.kmModel:SetMaterial( prevTMaterial )
        target.kmModel:SetRenderMode( target:GetRenderMode() )
        target.kmModel:SetOwner( target )

        if !target:IsNextBot() and IsValid( target:GetActiveWeapon() ) then 
            target.kmModel.Weapon = target:GetActiveWeapon() 
        end

        for _, bodygroup in ipairs( target:GetBodyGroups() ) do
            target.kmModel:SetBodygroup( bodygroup.id, target:GetBodygroup( bodygroup.id ) )
        end

        for _, ent in ipairs( target:GetChildren() ) do 
            ent:SetParent( target.kmModel, ent:GetParentAttachment() ) 
            ent:SetLocalPos( vector_origin )
            ent:SetLocalAngles( angle_zero )
        end 

        target.kmModel:Spawn()

        target.kmModel:AddEffects( EF_BONEMERGE )
        target.kmModel:SetParent( target.kmAnim )

        local fakeChildren
        if target.IsLambdaPlayer then
            fakeChildren = {}
            for _, child in ipairs( hiddenChildren2 ) do
                local fakeChild = ents_Create( "base_anim" )
                fakeChild:SetModel( child:GetModel() )
                fakeChild:SetPos( target.kmModel:GetPos() )
                fakeChild:SetAngles( target.kmModel:GetAngles() )
                fakeChild:SetOwner( target.kmModel )
                fakeChild:SetParent( target.kmModel )
                fakeChild:Spawn()
                fakeChild:AddEffects( EF_BONEMERGE )
                
                fakeChildren[ #fakeChildren + 1 ] = fakeChild
                target.kmModel:DeleteOnRemove( fakeChild )
            end

            target.l_BecomeRagdollEntity = target.kmModel 
        end

        self:DoKMEffects( animName, self.kmModel, target.kmModel )

        --Now for the timers

        SimpleTimer( targetKMTime, function()
            if !IsValid( target ) then return end
            target.kmAnim.AutomaticFrameAdvance = false

            SimpleTimer( 0.075, function()
                if !IsValid( target ) then return end

                target:SetHealth( 1 )
                target:DrawShadow( true )
                target.inKillMove = false

                if target:IsPlayer() then
                    target:SetMaterial( prevTMaterial )
                else
                    target:SetNoDraw( false )
                end

                if IsValid( target.kmModel ) then                
                    local bonePos = target.kmModel:GetBonePosition( 0 )                    
                    target:SetPos( Vector( bonePos.x, bonePos.y, target:GetPos().z ) ) 

                    for _, ent in ipairs( target.kmModel:GetChildren() ) do 
                        ent:SetParent( target, ent:GetParentAttachment() ) 
                        ent:SetLocalPos( vector_origin )
                        ent:SetLocalAngles( angle_zero )
                    end 

                    if fakeChildren then
                        for _, child in ipairs( fakeChildren ) do
                            if IsValid( child ) then child:Remove() end
                        end
                    end

                    target.kmModel:SetNoDraw( true )
                    target.kmModel:RemoveDelay( 2 )
                end
                if IsValid( target.kmAnim ) then target.kmAnim:RemoveDelay(2) end

                if target:IsPlayer() then
                    target:UnLock()

                    if target:Health() > 0 then
                        local dmginfo = DamageInfo()
                        dmginfo:SetAttacker( self )
                        dmginfo:SetDamageType( DMG_DIRECT )
                        dmginfo:SetDamage( 999999999999 )
                        target:TakeDamageInfo( dmginfo )

                        SimpleTimer( 0, function() if target:Health() > 0 then target:Kill() end end)
                    end
                elseif target.IsLambdaPlayer then
                    target:UnLock()

                    if target:Alive() then
                        target:ClientSideNoDraw( target, false )
                        target:PreventWeaponSwitch( false )

                        for _, child in ipairs( hiddenChildren2 ) do
                            if !IsValid( child ) then continue end
                            target:ClientSideNoDraw( child, false )
                            child:SetRenderMode( RENDERMODE_NORMAL )
                            child:DrawShadow( true )
                        end

                        local dmginfo = DamageInfo()
                        dmginfo:SetAttacker( self )
                        dmginfo:SetDamageType( DMG_DIRECT )
                        dmginfo:SetDamage( 999999999999 )
                        target:LambdaOnKilled( dmginfo )
                    else
                        net.Start( "lambdaplayers_bsmod_ragdollhook" )
                            net.WriteEntity( target )
                        net.Broadcast()
                    end
                elseif target:IsNPC() or target:IsNextBot() then
                    target:SetHealth( 0 )

                    local dmginfo = DamageInfo()
                    dmginfo:SetAttacker( self )
                    dmginfo:SetDamageType( DMG_SLASH )
                    dmginfo:SetDamage( 1 )
                    target:TakeDamageInfo( dmginfo )
                end
            end )
        end )
        
        SimpleTimer( plyKMTime, function()
            if !IsValid( self ) then return end
            self.kmAnim.AutomaticFrameAdvance = false
            
            SimpleTimer( 0.075, function()
                if !IsValid( self ) then return end
                self:DrawShadow( true )

                if self.IsLambdaPlayer then
                    self:ClientSideNoDraw( self, false )
                    self:SetNoDraw( false )

                    self:PreventWeaponSwitch( false )
                    self:SwitchWeapon( prevWeapon )

                    for _, child in ipairs( hiddenChildren ) do
                        if !IsValid( child ) then continue end
                        self:ClientSideNoDraw( child, false )
                        child:SetRenderMode( RENDERMODE_NORMAL )
                        child:DrawShadow( true )
                    end

                    self:SetCollisionGroup( COLLISION_GROUP_PLAYER )
                    self:GetPhysicsObject():EnableCollisions( true )
                else
                    self:SetMaterial( prevMaterial )
                    self:DrawWorldModel( true )
                    self:SetMoveType( MOVETYPE_WALK )

                    if IsValid( prevWeapon ) then
                        if prevWeapon:GetClass() != "weapon_bsmod_punch" then
                            self:StripWeapon( "weapon_bsmod_killmove" )
                        end
                        self:SelectWeapon( prevWeapon )
                    end
                end
                
                self:UnLock(); self.inKillMove = false
                if prevGodMode then self:GodDisable() end

                if IsValid( self.kmModel ) then 
                    for _, ent in ipairs( self.kmModel:GetChildren() ) do 
                        ent:SetParent( self, ent:GetParentAttachment() ) 
                        ent:SetLocalPos( vector_origin )
                        ent:SetLocalAngles( angle_zero )
                    end 

                    self.kmModel:Remove() 
                end
                if IsValid( self.kmAnim ) then
                    local headBone = self.kmAnim:GetAttachment( self.kmAnim:LookupAttachment( "eyes" ) )
                    self:SetPos( Vector( headBone.Pos.x, headBone.Pos.y, headBone.Pos.z + ( self:GetPos().z - self:EyePos().z ) ) )
                    self:SetEyeAngles( Angle( headBone.Ang.x, headBone.Ang.y, 0 ) )
                    self.kmAnim:Remove()
                end

                local healthToSpawn = 0
                if self:Health() < self:GetMaxHealth() then
                    if spawnHealthVials:GetBool() and spawnHealthKits:GetBool() then
                        healthToSpawn = random( 1, 2 )
                    else
                        if spawnHealthVials:GetBool() then
                            healthToSpawn = 1
                        elseif spawnHealthKits:GetBool() then
                            healthToSpawn = 2
                        end
                    end
                end
                if healthToSpawn == 1 then
                    local vial = ents_Create( "item_healthvial" )
                    vial:SetPos( self:GetPos() )
                    vial:Spawn()
                elseif healthToSpawn == 2 then
                    local kit = ents_Create( "item_healthkit" )
                    kit:SetPos( self:GetPos() )
                    kit:Spawn()
                end
            end, true )
        end, true )
    end

    local function LambdaSetEyeAngles( self, angles )
        angles.x = 0
        angles.z = 0
        self:SetAngles( angles )
    end

    local function IsBehindTarget( self, target )
        local vec = ( self:GetPos() - target:GetPos() ):GetNormal():Angle().y

        local targetAngle = target:EyeAngles().y
        if targetAngle > 360 then
            targetAngle = targetAngle - 360
        end
        if targetAngle < 0 then
            targetAngle = targetAngle + 360
        end

        local angleAround = ( vec - targetAngle )
        if angleAround > 360 then
            angleAround = angleAround - 360
        end
        if angleAround < 0 then
            angleAround = angleAround + 360
        end

        return ( angleAround > 135 and angleAround <= 225 )
    end

    local plyMeta = FindMetaTable( "Player" )
    plyMeta.KillMove = LambdaKillMove

    local function OnInitialize( self )
        self.KillMove = LambdaKillMove
        self.DoKMEffects = plyMeta.DoKMEffects
        self.SetEyeAngles = LambdaSetEyeAngles
    end

    local function OnThink( self, wepent )
        if self.l_BSMod_PrevKeepDistance then
            self.l_CombatKeepDistance = self.l_BSMod_PrevKeepDistance
            self.l_BSMod_PrevKeepDistance = nil
        end
        if self.l_BSMod_PrevAttackDistance then
            self.l_CombatAttackRange = self.l_BSMod_PrevAttackDistance
            self.l_BSMod_PrevAttackDistance = nil
        end

        if self.inKillMove then
            self.loco:SetVelocity( vector_origin )
            self:WaitWhileMoving( Rand( 0.1, 0.33 ) )

            if IsValid( self.kmModel ) then
                local rootPos = self.kmModel:GetBonePosition( 0 )
                local modelPos = ( rootPos - self:GetUp() * ( self:WorldSpaceCenter():Distance( self:GetPos() ) ) )
                self:SetPos( modelPos )
            end
        end

        local enemy = self:GetEnemy()
        if self:GetState() == "Combat" and LambdaIsValid( enemy ) then 
            if enemy.inKillMove then
                self:SetEnemy( NULL )
                self:CancelMovement()
                return
            end

            if !self.inKillMove and allowKillMoves:GetBool() and ( enemy.killMovable or killMoveAlways:GetBool() or killMoveBehind:GetBool() and IsBehindTarget( self, enemy ) and self:CanSee( enemy ) ) and ( !enemy:IsNPC() and ( !enemy:IsNextBot() or enemy.IsLambdaPlayer ) or killMoveNPCs:GetBool() ) and ( !enemy:IsPlayer() or !enemy:HasGodMode() and killMovePlayers:GetBool() ) then
                local isApproachable = ( enemy.IsLambdaPlayer and ( enemy:GetState() != "Combat" or enemy:GetEnemy() != self ) or enemy:IsNPC() and enemy.GetEnemy and enemy:GetEnemy() != self )
                if isApproachable and dontAttackKillMoveables:GetBool() then
                    self.l_BSMod_PrevAttackDistance = self.l_CombatAttackRange
                    self.l_CombatAttackRange = 0
                end
                if isApproachable or enemy.IsLambdaPlayer and enemy:GetIsReloading() or self:IsInRange( enemy, 300 ) then
                    self.l_BSMod_PrevKeepDistance = self.l_CombatKeepDistance
                    self.l_CombatKeepDistance = 0
                end

                if self:IsInRange( enemy, 80 ) then 
                    self:LookTo( enemy:WorldSpaceCenter(), 0.33 )
                    KMCheck( self )
                end
            end
        end
    end

    local function OnCanTarget( self, target )
        if target.inKillMove then return true end
    end

    local function OnCanSwitchWeapon( self )
        if self.inKillMove then return true end
    end

    hook.Add( "LambdaOnInitialize", "LambdaBSMod_OnInitialize", OnInitialize )
    hook.Add( "LambdaOnThink", "LambdaBSMod_OnThink", OnThink )
    hook.Add( "LambdaCanTarget", "LambdaBSMod_OnCanTarget", OnCanTarget )
    hook.Add( "LambdaCanSwitchWeapon", "LambdaBSMod_OnCanSwitchWeapon", OnCanSwitchWeapon )
    hook.Add( "LambdaFootStep", "LambdaBSMod_OnLambdaFootStep", OnCanSwitchWeapon )

end