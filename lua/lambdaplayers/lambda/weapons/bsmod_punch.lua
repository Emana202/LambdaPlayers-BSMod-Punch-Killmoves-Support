if !file.Exists( "weapons/weapon_bsmod_punch.lua", "LUA" ) then return end

local IsValid = IsValid
local CurTime = CurTime
local random = math.random
local Rand = math.Rand
local ceil = math.ceil
local EffectData = EffectData
local ScreenShake = util.ScreenShake
local util_Effect = util.Effect
local punchDmgMin = GetConVar( "bsmod_punch_damage_min" )
local punchDmgMax = GetConVar( "bsmod_punch_damage_max" )
local punchEffect = GetConVar( "bsmod_punch_effect" )
local blockResist = GetConVar( "bsmod_punch_blocking_resistance" )
local meleeBulletTbl = {
    Num = 1,
    Spread = vector_origin,
    Tracer = 0,
    Force = 20,
    HullSize = 1,
    Distance = 75
}

table.Merge( _LAMBDAPLAYERSWEAPONS, {
    bsmod_punch = {
        model = "",
        origin = "Misc",
        prettyname = "BSMod Punch",
        holdtype = "fist",
        killicon = "lambdaplayers/killicons/icon_fists",
        ismelee = true,
        nodraw = true,
        keepdistance = 12,
        attackrange = 70,

        OnDeploy = function( self, wepent )
            self.l_BSModBlockTime = nil
            self:SimpleTimer( 0.1, function() wepent:EmitSound( "player/fists/fists_crackl.wav" ) end )
            self:SimpleTimer( 0.5, function() wepent:EmitSound( "player/fists/fists_crackr.wav" ) end )
        end,

        OnHolster = function( self, wepent )
            self.l_BSModBlockTime = nil
        end,

        OnTakeDamage = function( self, wepent, dmginfo )
            if !self.l_BSModBlockTime and random( 1, 10 ) == 1 and !dmginfo:IsDamageType( DMG_FALL + DMG_BURN + DMG_DROWN + DMG_POISON + DMG_SLOWBURN + DMG_DROWNRECOVER ) then 
                self.l_BSModBlockTime = CurTime() + Rand( 0.2, 1.0 )
            end

            if self.l_BSModBlockTime then
                local dmg = dmginfo:GetDamage()
                dmginfo:SetDamage( dmg - ceil( ( dmg / 100 ) * blockResist:GetInt() ) )
                
                self:SimpleTimer( 0, function() 
                    if !self.killMovable then return end
                    self:SetKillMovable( false ) 
                end )
            end
        end,

        OnThink = function( self, wepent, isdead )
            if !isdead and self.l_BSModBlockTime then 
                if CurTime() <= self.l_BSModBlockTime then
                    self:AddGesture( ACT_HL2MP_FIST_BLOCK )
                else
                    self.l_BSModBlockTime = nil
                    self:RemoveGesture( ACT_HL2MP_FIST_BLOCK )
                end
            end
        end,

        OnAttack = function( self, wepent, target )
            if self.l_BSModBlockTime then return true end
            self.l_WeaponUseCooldown = CurTime() + Rand( 0.175, 0.35 )

            wepent:EmitSound( "player/fists/fists_fire0" .. random( 1, 3 ) .. ".wav", 100, 100, 1, CHAN_AUTO )

            self:RemoveGesture( ACT_HL2MP_GESTURE_RANGE_ATTACK_FIST )
            self:AddGesture( ACT_HL2MP_GESTURE_RANGE_ATTACK_FIST, true )

            self:SimpleTimer( 0.1, function()
                local aimDir = ( IsValid( target ) and ( target:WorldSpaceCenter() - self:GetAttachmentPoint( "eyes" ).Pos ):GetNormalized() or self:GetForward() )

                meleeBulletTbl.Attacker = self
                meleeBulletTbl.IgnoreEntity = self
                meleeBulletTbl.Damage = random( punchDmgMin:GetInt(), punchDmgMax:GetInt() )
                meleeBulletTbl.Src = self:GetAttachmentPoint( "eyes" ).Pos
                meleeBulletTbl.Dir = aimDir
                meleeBulletTbl.Callback = function( ply, tr, damageinfo )
                    if IsFirstTimePredicted() and punchEffect:GetBool() then
                        local fx = EffectData()
                        fx:SetStart( tr.HitPos )
                        fx:SetOrigin( tr.HitPos )
                        fx:SetNormal( tr.HitNormal )
                        util_Effect( "kick_groundhit", fx )
                    end

                    local trEnt = tr.Entity
                    if trEnt:IsNPC() or trEnt:IsPlayer() then
                        tr.Entity:SetVelocity( Vector( aimDir.x, aimDir.y, 0 ) * 250 )
                        wepent:EmitSound( "player/fists/fists_hit0" .. random( 1, 3 ) .. ".wav", 100, 100, 1, CHAN_AUTO )
                    else
                        wepent:EmitSound( "player/fists/fists_miss0" .. random( 1, 3 ) .. ".wav", 100, 100, 1, CHAN_AUTO )
                    end

                    ScreenShake( tr.HitPos, 0.5, 10, 0.5, 250 )
                end
                
                wepent:FireBullets( meleeBulletTbl, false ) 
            end )

            return true
        end,
        
        islethal = true
    }
} )