//A biomass source denotes some form of biomass income added to the marker. These are inherently limited.
/datum/biomass_source
	var/initial_mass	=	0
	var/remaining_mass	=	0	//How much total mass is left to be absorbed
	var/mass_tick	=	1	//How much mass is taken at each tick. IE, per second
	var/datum/source = null	//The atom or thing we are drawing biomass from. Optional
	var/datum/target	=	null	//The thing that is absorbing the source. Generally this is a marker
	var/sourcename

/datum/biomass_source/New(var/datum/_source = null, var/datum/_target = null, var/total_mass = 0, var/duration = 1 SECOND)
	.=..()
	source = "\ref[_source]"
	if (istype(_source, /atom))
		var/atom/A = _source
		sourcename = A.name
	target = _target
	initial_mass = total_mass
	remaining_mass = total_mass
	calculate_tick(total_mass, duration)

//Do any desired checks here
/datum/biomass_source/proc/can_absorb()
	if (remaining_mass > 0)
		return MASS_READY
	else
		return MASS_EXHAUST

//Subtracts mass from the total and returns it
/datum/biomass_source/proc/absorb()

	var/quantity = min(mass_tick, remaining_mass)
	remaining_mass -= quantity
	return quantity


//Takes a list of existing biomass sources, returns true if we are a duplicate of one already in there
//Override this proc to alter or disable this behaviour
/datum/biomass_source/proc/is_duplicate(var/list/stack)
	if (!source)
		return FALSE	//If we don't have a source we're not a duplicate

	//Same source and type? Its duplicate
	for (var/datum/biomass_source/S as anything in stack)
		if (S.source == source && S.type == type)
			return TRUE

	return FALSE


/datum/biomass_source/proc/calculate_tick(var/mass, var/duration)
	mass_tick = mass / (duration * 0.1)	//Calculate the mass absorbed per second

/datum/biomass_source/proc/mass_exhausted()
	return
	//Called when this source runs out of biomass to absorb, but before it is deleted. Do any final stuff here


//Baseline income
//-----------------------
/datum/biomass_source/baseline
	remaining_mass = 9999999999999	//Never runs out
	mass_tick = 0.1

/datum/biomass_source/baseline/New()
	..()
	remaining_mass = initial(remaining_mass)
	mass_tick = initial(mass_tick)

/datum/biomass_source/baseline/absorb()
	return mass_tick

/datum/biomass_source/baseline/calculate_tick()
	return	//Tick is flat, not calculated



//Reclaiming broken necromorphs
//-------------------------------
/datum/biomass_source/reclaim


//Absorbing dead humans
//------------------------
/datum/biomass_source/convergence

//Todo here: Check if the human body is near enough to the marker, or some sort of corruption-corpse-deposit node
//If its too far away, return pause
/datum/biomass_source/convergence/can_absorb()

	var/mob/living/L = locate(source)
	if (!L || QDELETED(L))
		return MASS_FAIL	//Its gone!

	//Lets check if its dead
	if (L.stat != DEAD)
		return MASS_PAUSE	//If we're still alive, keep waiting

	//Are we still near the marker?
	if (get_dist(L, target) > 10)
		for (var/obj/structure/corruption_node/maw/M in range(MAW_EAT_RANGE, L))
			return ..()
		return MASS_PAUSE

	return ..()

/datum/biomass_source/convergence/absorb()
	.=..()
	var/mob/L = locate(source)
	if (ishuman(L) && remaining_mass)

		var/mob/living/carbon/human/H = L
		//As a human is absorbed, lets remove their limbs one by one
		//1. figure out how far along the absorbing process we are
		var/remaining = 	remaining_mass / initial_mass
		//2. Now that we have a percentage, lets figure out how many remaining limbs that equates to
		var/remaining_organs = Ceiling(H.species.has_limbs.len * remaining)
		//3. If the number of organs we have is above that number, then we'll lose one
		if (LAZYLEN(H.organs) > remaining_organs)
			var/obj/item/organ/external/toremove = pick(H.get_extremities())
			toremove.droplimb(clean = TRUE, silent = TRUE)
			qdel(toremove)//It is devoured, no trace left


//Once we've completely absorbed our source, there's nothing left. Delete them.
//This will consume worn equipment too, maybe thats desireable
/datum/biomass_source/convergence/mass_exhausted()
	qdel(source)




/*
	Helper Procs
*/

/proc/get_biomass_sources()
	var/list/sources = list()
	var/obj/machinery/marker/M	= get_marker()
	sources += M.biomass_sources

	//Possible future todo here: Support for multiple markers or biomass holders

	return sources

//Called when the biomass of a live mob changes at any time other than initial spawning
/mob/living/proc/adjust_biomass(var/change)
	//Account for the possibility of going sub zero
	if ((biomass + change) < 0)
		change = biomass * -1

	//Set the biomass
	biomass += change

	//Now we search through all biomass sources to find one where the source equals us
	var/list/sources = get_biomass_sources()
	for (var/datum/biomass_source/BS in sources)
		var/atom/A = locate(BS.source)
		if (!A)
			continue

		//Ding!
		if (A == src)
			BS.initial_mass += change
			BS.remaining_mass += change


//How much biomass is this object worth?
/atom/proc/get_biomass()
	return 0


/mob/living/get_biomass()
	return biomass


/obj/get_biomass()
	return biomass


/obj/item/weapon/reagent_containers/food/snacks/get_biomass()
	return (nutriment_amt * 0.1)