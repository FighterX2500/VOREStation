/obj/item/device/uplink
	var/welcome = "Welcome, Operative"	// Welcoming menu message
	var/uses 							// Numbers of crystals
	var/list/ItemsCategory				// List of categories with lists of items
	var/list/ItemsReference				// List of references with an associated item
	var/list/nanoui_items				// List of items for NanoUI use
	var/nanoui_menu = 0					// The current menu we are in
	var/list/nanoui_data = new 			// Additional data for NanoUI use
	var/faction = ""					//Antag faction holder.

	var/list/purchase_log = new
	var/datum/mind/uplink_owner = null
	var/used_TC = 0
	var/offer_time = 10 MINUTES			//The time increment per discount offered
	var/next_offer_time					//The time a discount will next be offered
	var/datum/uplink_item/discount_item	//The item to be discounted
	var/discount_amount					//The amount as a percent the item will be discounted by

/obj/item/device/uplink/nano_host()
	return loc

/obj/item/device/uplink/New(var/location, var/datum/mind/owner = null, var/telecrystals = DEFAULT_TELECRYSTAL_AMOUNT)
	..()
	src.uplink_owner = owner
	purchase_log = list()
	world_uplinks += src
	if(owner)
		uses = owner.tcrystals
	else
		uses = telecrystals
	processing_objects += src

/obj/item/device/uplink/Destroy()
	world_uplinks -= src
	processing_objects -= src
	return ..()

/obj/item/device/uplink/get_item_cost(var/item_type, var/item_cost)
	return (discount_item && (item_type == discount_item)) ? max(1, round(item_cost*discount_amount)) : item_cost

// HIDDEN UPLINK - Can be stored in anything but the host item has to have a trigger for it.
/* How to create an uplink in 3 easy steps!

 1. All obj/item 's have a hidden_uplink var. By default it's null. Give the item one with "new(src)", it must be in it's contents. Feel free to add "uses".

 2. Code in the triggers. Use check_trigger for this, I recommend closing the item's menu with "usr << browse(null, "window=windowname") if it returns true.
 The var/value is the value that will be compared with the var/target. If they are equal it will activate the menu.

 3. If you want the menu to stay until the users locks his uplink, add an active_uplink_check(mob/user as mob) in your interact/attack_hand proc.
 Then check if it's true, if true return. This will stop the normal menu appearing and will instead show the uplink menu.
*/

/obj/item/device/uplink/hidden
	name = "hidden uplink"
	desc = "There is something wrong if you're examining this."
	var/active = 0
	var/datum/uplink_category/category 	= 0		// The current category we are in
	var/exploit_id								// Id of the current exploit record we are viewing

// The hidden uplink MUST be inside an obj/item's contents.
/obj/item/device/uplink/hidden/New()
	spawn(2)
		if(!istype(src.loc, /obj/item))
			qdel(src)
	..()
	nanoui_data = list()
	update_nano_data()

/obj/item/device/uplink/hidden/process()
	if(world.time > next_offer_time)
		discount_item = default_uplink_selection.get_random_item(INFINITY)
		discount_amount = pick(90;0.9, 80;0.8, 70;0.7, 60;0.6, 50;0.5, 40;0.4, 30;0.3, 20;0.2, 10;0.1)
		next_offer_time = world.time + offer_time
		update_nano_data()
		nanomanager.update_uis(src)

// Toggles the uplink on and off. Normally this will bypass the item's normal functions and go to the uplink menu, if activated.
/obj/item/device/uplink/hidden/proc/toggle()
	active = !active

// Directly trigger the uplink. Turn on if it isn't already.
/obj/item/device/uplink/hidden/proc/trigger(mob/user as mob)
	if(!active)
		toggle()
	interact(user)

// Checks to see if the value meets the target. Like a frequency being a traitor_frequency, in order to unlock a headset.
// If true, it accesses trigger() and returns 1. If it fails, it returns false. Use this to see if you need to close the
// current item's menu.
/obj/item/device/uplink/hidden/proc/check_trigger(mob/user as mob, var/value, var/target)
	if(value == target)
		trigger(user)
		return 1
	return 0

/*
	NANO UI FOR UPLINK WOOP WOOP
*/
/obj/item/device/uplink/hidden/ui_interact(mob/user, ui_key = "main", var/datum/nanoui/ui = null, var/force_open = 1)
	var/title = "Remote Uplink"
	var/data[0]
	uses = user.mind.tcrystals
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		faction = H.antag_faction

	data["welcome"] = welcome
	data["crystals"] = uses
	data["menu"] = nanoui_menu
	data += nanoui_data

	// update the ui if it exists, returns null if no ui is passed/found
	ui = nanomanager.try_update_ui(user, src, ui_key, ui, data, force_open)
	if (!ui)	// No auto-refresh
		ui = new(user, src, ui_key, "uplink.tmpl", title, 450, 600, state = inventory_state)
		data["menu"] = 0
		ui.set_initial_data(data)
		ui.open()


// Interaction code. Gathers a list of items purchasable from the paren't uplink and displays it. It also adds a lock button.
/obj/item/device/uplink/hidden/interact(mob/user)
	ui_interact(user)

/obj/item/device/uplink/hidden/CanUseTopic()
	if(!active)
		return STATUS_CLOSE
	return ..()

// The purchasing code.
/obj/item/device/uplink/hidden/Topic(href, href_list)
	if(..())
		return 1

	var/mob/user = usr
	if(href_list["buy_item"])
		var/datum/uplink_item/UI = (locate(href_list["buy_item"]) in uplink.items)
		UI.buy(src, usr)
	else if(href_list["lock"])
		toggle()
		var/datum/nanoui/ui = nanomanager.get_open_ui(user, src, "main")
		ui.close()
	else if(href_list["return"])
		nanoui_menu = round(nanoui_menu/10)
	else if(href_list["menu"])
		nanoui_menu = text2num(href_list["menu"])
		if(href_list["id"])
			exploit_id = href_list["id"]
		if(href_list["category"])
			category = locate(href_list["category"]) in uplink.categories

	update_nano_data()
	return 1

/obj/item/device/uplink/hidden/proc/update_nano_data()
	if(nanoui_menu == 0)
		var/categories[0]
		for(var/datum/uplink_category/category in uplink.categories)
			if(category.can_view(src))
				categories[++categories.len] = list("name" = category.name, "ref" = "\ref[category]")
		nanoui_data["categories"] = categories
		nanoui_data["discount_name"] = discount_item ? discount_item.name : ""
		nanoui_data["discount_amount"] = (1-discount_amount)*100
		nanoui_data["offer_expiry"] = worldtime2stationtime(next_offer_time)
	else if(nanoui_menu == 1)
		var/items[0]
		for(var/datum/uplink_item/item in category.items)
			if(item.can_view(src))
				var/cost = item.cost(uses, src)
				if(!cost) cost = "???"
				items[++items.len] = list("name" = item.name, "description" = replacetext(item.description(), "\n", "<br>"), "can_buy" = item.can_buy(src), "cost" = cost, "ref" = "\ref[item]")
		nanoui_data["items"] = items
	else if(nanoui_menu == 2)
		var/permanentData[0]
		for(var/datum/data/record/L in sortRecord(data_core.locked))
			permanentData[++permanentData.len] = list(Name = L.fields["name"],"id" = L.fields["id"])
		nanoui_data["exploit_records"] = permanentData
	else if(nanoui_menu == 21)
		nanoui_data["exploit_exists"] = 0

		for(var/datum/data/record/L in data_core.locked)
			if(L.fields["id"] == exploit_id)
				nanoui_data["exploit"] = list()  // Setting this to equal L.fields passes it's variables that are lists as reference instead of value.
								 // We trade off being able to automatically add shit for more control over what gets passed to json
								 // and if it's sanitized for html.
				nanoui_data["exploit"]["nanoui_exploit_record"] = lhtml_encode(L.fields["exploit_record"])                         		// Change stuff into html
				nanoui_data["exploit"]["nanoui_exploit_record"] = replacetext(nanoui_data["exploit"]["nanoui_exploit_record"], "\n", "<br>")    // change line breaks into <br>
				nanoui_data["exploit"]["name"] =  lhtml_encode(L.fields["name"])
				nanoui_data["exploit"]["sex"] =  lhtml_encode(L.fields["sex"])
				nanoui_data["exploit"]["age"] =  lhtml_encode(L.fields["age"])
				nanoui_data["exploit"]["species"] =  lhtml_encode(L.fields["species"])
				nanoui_data["exploit"]["rank"] =  lhtml_encode(L.fields["rank"])
				nanoui_data["exploit"]["home_system"] =  lhtml_encode(L.fields["home_system"])
				nanoui_data["exploit"]["citizenship"] =  lhtml_encode(L.fields["citizenship"])
				nanoui_data["exploit"]["faction"] =  lhtml_encode(L.fields["faction"])
				nanoui_data["exploit"]["religion"] =  lhtml_encode(L.fields["religion"])
				nanoui_data["exploit"]["fingerprint"] =  lhtml_encode(L.fields["fingerprint"])
				if(L.fields["antagvis"] == ANTAG_KNOWN || (faction == L.fields["antagfac"] && (L.fields["antagvis"] == ANTAG_SHARED)))
					nanoui_data["exploit"]["antagfaction"] = lhtml_encode(L.fields["antagfac"])
				else
					nanoui_data["exploit"]["antagfaction"] = lhtml_encode("None")
				nanoui_data["exploit_exists"] = 1
				break

// I placed this here because of how relevant it is.
// You place this in your uplinkable item to check if an uplink is active or not.
// If it is, it will display the uplink menu and return 1, else it'll return false.
// If it returns true, I recommend closing the item's normal menu with "user << browse(null, "window=name")"
/obj/item/proc/active_uplink_check(mob/user as mob)
	// Activates the uplink if it's active
	if(src.hidden_uplink)
		if(src.hidden_uplink.active)
			src.hidden_uplink.trigger(user)
			return 1
	return 0

// PRESET UPLINKS
// A collection of preset uplinks.
//
// Includes normal radio uplink, multitool uplink,
// implant uplink (not the implant tool) and a preset headset uplink.

/obj/item/device/radio/uplink/New(atom/loc, datum/mind/target_mind, telecrystals)
	..(loc)
	hidden_uplink = new(src, target_mind, telecrystals)
	icon_state = "radio"

/obj/item/device/radio/uplink/attack_self(mob/user as mob)
	if(hidden_uplink)
		hidden_uplink.trigger(user)

/obj/item/device/multitool/uplink/New()
	hidden_uplink = new(src)

/obj/item/device/multitool/uplink/attack_self(mob/user as mob)
	if(hidden_uplink)
		hidden_uplink.trigger(user)

/obj/item/device/radio/headset/uplink
	traitor_frequency = 1445

/obj/item/device/radio/headset/uplink/New()
	..()
	hidden_uplink = new(src)
	hidden_uplink.uses = DEFAULT_TELECRYSTAL_AMOUNT
