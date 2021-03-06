/*
	Corruption is an extension of the bay spreading plants system.

	Corrupted tiles spread out gradually from the marker, and from any placed nodes, up to a certain radius
*/
GLOBAL_LIST_EMPTY(corruption_sources)
GLOBAL_DATUM_INIT(corruption_seed, /datum/seed/corruption, new())

//We'll be using a subtype in addition to a seed, becuase there's a lot of special case behaviour here
/obj/effect/vine/corruption
	name = "corruption"
	icon = 'icons/effects/corruption.dmi'
	icon_state = ""

	max_health = 80
	max_growth = 1

	var/max_alpha = 215
	var/min_alpha = 20

	spread_chance = 100	//No randomness in this, spread as soon as its ready
	spread_distance = CORRUPTION_SPREAD_RANGE	//One node creates a screen-sized patch of corruption
	growth_type = 0
	var/vine_scale = 1.1
	var/datum/extension/corruption_source/source


/obj/effect/vine/corruption/New(var/newloc, var/datum/seed/newseed, var/obj/effect/vine/corruption/newparent, var/start_matured = 0, var/datum/extension/corruption_source/newsource)

	alpha = min_alpha
	GLOB.necrovision.add_source(src)	//Corruption tiles add vision

	if (!GLOB.corruption_seed)
		GLOB.corruption_seed = new /datum/seed/corruption()
	seed = GLOB.corruption_seed

	source = newsource
	if (!newsource)
		source = newparent.source
	source.register(src)
	.=..()

//Corruption tiles reveal their own tile, and surrounding dense obstacles. They will not reveal surrounding clear tiles
/obj/effect/vine/corruption/get_visualnet_tiles(var/datum/visualnet/network)
	var/list/visible_tiles = list(get_turf(src))
	for (var/turf/T in orange(1, src))
		if (!turf_clear(T))
			visible_tiles.Add(T)

	return visible_tiles


//No calculating, we'll input all these values in the variables above
/obj/effect/vine/corruption/calculate_growth()

	mature_time = rand_between(20 SECONDS, 30 SECONDS) / source.growth_speed	//How long it takes for one tile to mature and be ready to spread into its neighbors.
	mature_time *= 1 + (source.growth_distance_falloff * get_dist_3D(src, plant))	//Expansion gets slower as you get farther out. Additively stacking 15% increase per tile

	growth_threshold = max_health
	possible_children = INFINITY
	return

/obj/effect/vine/corruption/update_icon()
	icon_state = "corruption-[rand(1,3)]"


	var/matrix/M = matrix()
	M = M.Scale(vine_scale)	//We scale up the sprite so it slightly overlaps neighboring corruption tiles
	var/rotation = pick(list(0,90,180,270))	//Randomly rotate it
	transform = turn(M, rotation)

	//Lets add the edge sprites
	overlays.Cut()
	for(var/turf/simulated/floor/floor in get_neighbors(FALSE, FALSE))
		var/direction = get_dir(src, floor)
		var/vector2/offset = Vector2.FromDir(direction)
		offset *= (WORLD_ICON_SIZE * vine_scale)
		var/image/I = image(icon, src, "corruption-edge", layer+1, direction)
		I.pixel_x = offset.x
		I.pixel_y = offset.y
		I.appearance_flags = RESET_TRANSFORM	//We use reset transform to not carry over the rotation

		I.transform = I.transform.Scale(vine_scale)	//We must reapply the scale
		overlays.Add(I)


//Corruption gradually fades in/out as its health goes up/down
/obj/effect/vine/corruption/adjust_health(value)
	.=..()
	if (health > 0)
		var/healthpercent = health / max_health
		alpha = min_alpha + ((max_alpha - min_alpha) * healthpercent)


//Add the effect from being on corruption
/obj/effect/vine/corruption/Crossed(atom/movable/O)
	if (isliving(O))
		var/mob/living/L = O
		if (!has_extension(L, /datum/extension/corruption_effect) && L.stat != DEAD)
			set_extension(L, /datum/extension/corruption_effect)


//This proc finds any viable corruption source to use for us
/obj/effect/vine/corruption/proc/find_corruption_host()

	for (var/datum/extension/corruption_source/CS in GLOB.corruption_sources)
		if (CS.can_support(src))
			return CS

	return null



//Gradually dies off without a nearby host
/obj/effect/vine/corruption/Process()
	.=..()
	if (!plant)
		adjust_health(-(SSplants.wait*0.1))	//Plant subsystem has a 6 second delay oddly, so compensate for it here


/obj/effect/vine/corruption/can_regen()
	.=..()
	if (.)
		if (!plant || QDELETED(plant))
			return FALSE

//In addition to normal checks, we need a place to put our plant
/obj/effect/vine/corruption/can_spawn_plant()
	if (!plant || QDELETED(plant))
		return TRUE
	return FALSE

//We can only place plants under a marker or growth node
//And before placing, we should look for an existing one
/obj/effect/vine/corruption/spawn_plant()
	var/datum/extension/corruption_source/CS = find_corruption_host()
	if (!CS)
		plant = null
		return
	if (CS.register(src))
		calculate_growth()



/obj/effect/vine/corruption/is_necromorph()
	return TRUE

/obj/effect/vine/corruption/can_spread_to(var/turf/floor)
	if (source.can_support(floor))
		return TRUE

	//Possible future todo: See if any other nodes can support it if our parent can't?

	return FALSE


/obj/effect/vine/corruption/wake_up(var/wake_adjacent = TRUE)
	.=..()
	if (plant && !QDELETED(plant))
		calculate_growth()


/*
	Spreading Logic
*/
/datum/extension/corruption_source
	expected_type = /atom
	flags = EXTENSION_FLAG_IMMEDIATE
	var/range = 12
	var/growth_speed = 1	//Multiplier on growth speed
	var/growth_distance_falloff = 0.15	//15% added to growth time for each tile of distance from the source
	var/atom/source
	var/obj/machinery/portable_atmospherics/hydroponics/soil/invisible/plant
	var/list/corruption_vines = list()	//A list of all the vines we're currently supporting


/datum/extension/corruption_source/New(var/atom/holder, var/range, var/speed, var/falloff)
	source = holder
	GLOB.corruption_sources |= src
	plant = new (source.loc, GLOB.corruption_seed)
	GLOB.moved_event.register(source, src, /datum/extension/corruption_source/proc/source_moved)
	if (range)
		src.range = range
	if (speed)
		growth_speed = speed
	if (falloff)
		growth_distance_falloff = falloff


	new /obj/effect/vine/corruption(get_turf(source),GLOB.corruption_seed, start_matured = 1, newsource = src)

/datum/extension/corruption_source/Destroy()
	GLOB.corruption_sources -= src
	qdel(plant)
	update_vines()
	.=..()



/datum/extension/corruption_source/proc/register(var/obj/effect/vine/corruption/applicant)

	if (!can_support(applicant))

		return FALSE
	corruption_vines |= applicant
	applicant.plant = plant
	applicant.source = src


//Is this source able to provide support to a specified turf or corruption vine?
/datum/extension/corruption_source/proc/can_support(var/atom/A)

	var/turf/T = get_turf(A)
	var/distance = get_dist_3D(get_turf(source), T)
	//We check distance fist, it's quick and efficient
	if (distance > range)
		return FALSE

	//TODO Future:
		//View restricting
		//Hard limit on supported quantity

	return TRUE


/datum/extension/corruption_source/proc/source_moved(var/atom/movable/mover, var/old_loc, var/new_loc)
	plant.forceMove(new_loc)
	update_vines()


//Called when a source moves, gets deleted, changes its radius or other parameters.
//Tells all the associated vines to update various things, and/or find a new parent to support them now that we're gone
//If we are being deleted, plant will be nulled out before calling this
/datum/extension/corruption_source/proc/update_vines()
	for (var/obj/effect/vine/corruption/C as anything in corruption_vines)
		C.wake_up(FALSE)





/* The seed */
//-------------------
/datum/seed/corruption
	display_name = "Corruption"
	no_icon = TRUE
	growth_stages = 1


/datum/seed/corruption/New()
	set_trait(TRAIT_IMMUTABLE,            1)            // If set, plant will never mutate. If -1, plant is highly mutable.
	set_trait(TRAIT_SPREAD,               2)            // 0 limits plant to tray, 1 = creepers, 2 = vines.
	set_trait(TRAIT_MATURATION,           0)            // Time taken before the plant is mature.
	set_trait(TRAIT_PRODUCT_ICON,         0)            // Icon to use for fruit coming from this plant.
	set_trait(TRAIT_PLANT_ICON,           'icons/effects/corruption.dmi')            // Icon to use for the plant growing in the tray.
	set_trait(TRAIT_PRODUCT_COLOUR,       0)            // Colour to apply to product icon.
	set_trait(TRAIT_POTENCY,              1)            // General purpose plant strength value.
	set_trait(TRAIT_REQUIRES_NUTRIENTS,   0)            // The plant can starve.
	set_trait(TRAIT_REQUIRES_WATER,       0)            // The plant can become dehydrated.
	set_trait(TRAIT_WATER_CONSUMPTION,    0)            // Plant drinks this much per tick.
	set_trait(TRAIT_LIGHT_TOLERANCE,      INFINITY)            // Departure from ideal that is survivable.
	set_trait(TRAIT_TOXINS_TOLERANCE,     INFINITY)            // Resistance to poison.
	set_trait(TRAIT_HEAT_TOLERANCE,       20)           // Departure from ideal that is survivable.
	set_trait(TRAIT_LOWKPA_TOLERANCE,     0)           // Low pressure capacity.
	set_trait(TRAIT_ENDURANCE,            100)          // Maximum plant HP when growing.
	set_trait(TRAIT_HIGHKPA_TOLERANCE,    INFINITY)          // High pressure capacity.
	set_trait(TRAIT_IDEAL_HEAT,           293)          // Preferred temperature in Kelvin.
	set_trait(TRAIT_NUTRIENT_CONSUMPTION, 0)         // Plant eats this much per tick.
	set_trait(TRAIT_PLANT_COLOUR,         "#ffffff")    // Colour of the plant icon.


/datum/seed/corruption/update_growth_stages()
	growth_stages = 1




/* Crossing Effect */
//-------------------
//Any mob that walks over a corrupted tile recieves this effect. It does varying things
	//On most mobs, it applies a slow to movespeed
	//On necromorphs, it applies a passive healing instead

/datum/extension/corruption_effect
	name = "Corruption Effect"
	expected_type = /mob/living
	flags = EXTENSION_FLAG_IMMEDIATE

	//Effects on necromorphs
	var/healing_per_tick = 1
	var/speedup = 1.15

	//Effects on non necros
	var/slowdown = 0.7	//Multiply speed by this


	var/speed_delta	//What absolute value we removed from the movespeed factor. This is cached so we can reverse it later

	var/necro = FALSE


/datum/extension/corruption_effect/New(var/datum/holder)
	.=..()
	var/mob/living/L = holder
	var/speed_factor = 0
	if (L.is_necromorph())
		necro = TRUE
		speed_factor = speedup //Necros are sped up
		to_chat(L, SPAN_DANGER("The corruption beneath speeds your passage and mends your vessel."))
	else
		to_chat(L, SPAN_DANGER("This growth underfoot is sticky and slows you down."))
		speed_factor = slowdown	//humans are slowed down

	var/newspeed = L.move_speed_factor * speed_factor
	speed_delta = L.move_speed_factor - newspeed
	L.move_speed_factor = newspeed

	START_PROCESSING(SSprocessing, src)


/datum/extension/corruption_effect/Process()
	var/mob/living/L = holder
	if (!L || !turf_corrupted(L) || L.stat == DEAD)
		//If the mob is no longer standing on a corrupted tile, we stop
		//Likewise if they're dead or gone
		remove_extension(holder, type)
		return PROCESS_KILL

	if (necro)
		L.heal_overall_damage(healing_per_tick)


/datum/extension/corruption_effect/Destroy()
	var/mob/living/L = holder
	if (istype(L))
		L.move_speed_factor += speed_delta	//Restore the movespeed to normal

	.=..()