local mod = get_mod("HoloJustice")

local CMD_SILLY_PROJ_HELP = [[
Enables or disabled the Silly Projectiles mod.
]]

local enabled = false

local original_projectile_trajectory = ProjectileTemplates.trajectory_templates.throw_trajectory

local crazy_gas_balls = {
    prediction_function = function (speed, gravity, initial_position, target_position, target_velocity)
        local t = 0
        local angle
        local EPSILON = 0.01
        local ITERATIONS = 10

        assert(gravity > 0, "Can't solve for <=0 gravity, use different projectile template")

        -- Add some initial randomness to the target position
        local chaos_factor = 0.3  -- How crazy the path is (0-1)
        local randomized_target = target_position + Vector3(
            (math.random() - 0.5) * chaos_factor * 5,
            (math.random() - 0.5) * chaos_factor * 5,
            (math.random() - 0.5) * chaos_factor * 2
        )

        local estimated_target_position = randomized_target

        for i = 1, ITERATIONS do
            -- Add some chaotic movement to the target estimation
            local time_offset = t * 2
            estimated_target_position = randomized_target + t * target_velocity + Vector3(
                math.sin(time_offset * 1.5) * chaos_factor * 3,
                math.cos(time_offset * 1.2) * chaos_factor * 3,
                (math.sin(time_offset * 0.8) * chaos_factor * 2)
            )

            local height = estimated_target_position.z - initial_position.z
            local speed_squared = speed^2
            local flat_distance = Vector3.length(Vector3.flat(estimated_target_position - initial_position))

            if flat_distance < EPSILON then
                return 0, estimated_target_position
            end

            local sqrt_val = speed_squared^2 - gravity * (gravity * flat_distance^2 + 2 * height * speed_squared)

            if sqrt_val <= 0 then
                -- Instead of returning nil, return a random angle to keep it interesting
                angle = math.random() * math.pi/4  -- Random angle up to 45 degrees
                return angle, estimated_target_position
            end

            local second_degree_component = math.sqrt(sqrt_val)
            local angle1 = math.atan((speed_squared + second_degree_component) / (gravity * flat_distance))
            local angle2 = math.atan((speed_squared - second_degree_component) / (gravity * flat_distance))

            -- Add some randomness to the selected angle
            angle = math.min(angle1, angle2) * (0.9 + math.random() * 0.2)

            local flat_distance = Vector3.length(Vector3.flat(estimated_target_position - initial_position))

            -- Add some chaos to the time calculation
            t = flat_distance / (speed * math.cos(angle)) * (0.8 + math.random() * 0.4)
        end

        -- Final randomized adjustment
        angle = angle * (0.8 + math.random() * 0.4)
        estimated_target_position = estimated_target_position + Vector3(
            (math.random() - 0.5) * chaos_factor * 2,
            (math.random() - 0.5) * chaos_factor * 2,
            (math.random() - 0.5) * chaos_factor
        )

        return angle, estimated_target_position
    end,
    unit = {
        update = function (speed, radians, gravity, initial_position, target_vector, time_lived, dt, optional_data)
            -- Add some chaotic movement to the actual projectile path
            local base_position = WeaponHelper:position_on_trajectory(initial_position, target_vector, speed, radians, gravity, time_lived, dt)
            
            -- Crazy offset calculations
            local time_factor = time_lived * 4
            local chaos_factor = 0.5  -- How much deviation from normal path
            
            local offset = Vector3(
                math.sin(time_factor * 1.7) * math.cos(time_factor * 0.9) * chaos_factor,
                math.cos(time_factor * 1.3) * math.sin(time_factor * 0.7) * chaos_factor,
                (math.sin(time_factor * 2.1) - math.cos(time_factor * 0.5)) * chaos_factor * 0.5
            )
            
            -- Occasionally add big jumps
            if math.random() < 0.02 then  -- 2% chance per frame
                offset = offset * 3 + Vector3(
                    (math.random() - 0.5) * 2,
                    (math.random() - 0.5) * 2,
                    math.random() * 1.5
                )
            end
            
            return base_position + offset
        end,
    },
    husk = {
        update = function (speed, radians, gravity, initial_position, target_vector, time_lived, dt, optional_data)
            -- Less crazy version for network sync
            local base_position = WeaponHelper:position_on_trajectory(initial_position, target_vector, speed, radians, gravity, time_lived, dt)
            
            local time_factor = time_lived * 2
            local chaos_factor = 0.2
            
            local offset = Vector3(
                math.sin(time_factor) * chaos_factor,
                math.cos(time_factor * 1.2) * chaos_factor,
                math.sin(time_factor * 0.8) * chaos_factor * 0.3
            )
            
            return base_position + offset
        end,
    },
}

mod:command("silly_proj", CMD_SILLY_PROJ_HELP, function(...)
    enabled = not enabled
    if enabled then
        ProjectileTemplates.trajectory_templates.throw_trajectory = crazy_gas_balls
        mod:echo("Silly Projectiles enabled")
    else
        ProjectileTemplates.trajectory_templates.throw_trajectory = original_projectile_trajectory
        mod:echo("Silly Projectiles disabled")
    end
end)