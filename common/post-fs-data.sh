#!/system/bin/sh
# Please don't hardcode /magisk/modname/... ; instead, please use $MODPATH/...
# This will make your scripts compatible even if Magisk change its mount point in the future
MODPATH=${0%/*}

# This script will be executed in post-fs-data mode
# More info in the main Magisk thread

# MagiskHide Props Config
# Copyright (c) 2018-2019 Didgeridoohan @ XDA Developers
# Licence: MIT

# Load functions
. $MODPATH/util_functions.sh

# Variables
IMGPATH=$(dirname "$MODPATH")
COREPATH=$(dirname "$IMGPATH")

# Start logging
log_start

# Clears out the script check file
rm -f $RUNFILE
touch $RUNFILE

# Clears out the script control file
touch $POSTCHKFILE

# Checks the reboot and print update variables in propsconf_late
if [ "$REBOOTCHK" == 1 ]; then
	replace_fn REBOOTCHK 1 0 $LATEFILE
fi
if [ "$PRINTCHK" == 1 ]; then
	replace_fn PRINTCHK 1 0 $LATEFILE
fi

# Check for the boot script and restore backup if deleted, or if the resetfile is present
if [ ! -f "$LATEFILE" ] || [ -f "$RESETFILE" ]; then
	if [ -f "$RESETFILE" ]; then
		RSTTXT="Resetting"
		rm -f $RESETFILE
	else
		RSTTXT="Restoring"
		log_handler "late_start service boot script not found."
	fi	
	log_handler "$RSTTXT late_start service boot script (${LATEFILE})."
	cp -af $MODPATH/propsconf_late $LATEFILE >> $LOGFILE 2>&1
	chmod -v 755 $LATEFILE >> $LOGFILE 2>&1
	placeholder_update $LATEFILE COREPATH CORE_PLACEHOLDER "$COREPATH"
	placeholder_update $LATEFILE CACHELOC CACHE_PLACEHOLDER "$CACHELOC"
fi

# Checks for the Universal SafetyNet Fix module and similar modules editing the device fingerprint
PRINTMODULE=false
for USNF in $USNFLIST; do
	if [ -d "$IMGPATH/$USNF" ]; then
		NAME=$(get_file_value $IMGPATH/$USNF/module.prop "name=")
		log_handler "'$NAME' installed (modifies the device fingerprint)."
		PRINTMODULE=true
	fi
done
if [ "$PRINTMODULE" == "true" ]; then
	replace_fn FINGERPRINTENB 1 0 $LATEFILE
	replace_fn PRINTMODULE 0 1 $LATEFILE
	log_handler "Fingerprint modification disabled."
else
	replace_fn FINGERPRINTENB 0 1 $LATEFILE
	replace_fn PRINTMODULE 1 0 $LATEFILE
fi

# Get default values
log_handler "Checking device default values."
curr_values
# Get the current original values saved in propsconf_late
log_handler "Loading currently saved values."
. $LATEFILE

# Save default file values in propsconf_late
for ITEM in $VALPROPSLIST; do
	TMPPROP=$(get_prop_type $ITEM | tr '[:lower:]' '[:upper:]')
	ORIGPROP="ORIG${TMPPROP}"
	ORIGTMP="$(eval "echo \$$ORIGPROP")"
	CURRPROP="CURR${TMPPROP}"
	CURRTMP="$(eval "echo \$$CURRPROP")"
	replace_fn $ORIGPROP "\"$ORIGTMP\"" "\"$CURRTMP\"" $LATEFILE
done
log_handler "Default values saved to $LATEFILE."

# Check if default file values are safe
orig_safe
# Loading the new values
. $LATEFILE

# Checks for configuration file
config_file

# Edits prop values if set for post-fs-data
echo -e "\n--------------------" >> $LOGFILE 2>&1
log_handler "Editing prop values in post-fs-data mode."
if [ "$OPTIONLATE" == 0 ]; then
	# ---Setting/Changing fingerprint---
	print_edit
	# ---Setting device simulation props---
	dev_sim_edit
	# ---Setting custom props---
	custom_edit "CUSTOMPROPS"
fi
# Deleting props
prop_del
# Edit custom props set for post-fs-data
custom_edit "CUSTOMPROPSPOST"
echo -e "\n--------------------" >> $LOGFILE 2>&1

# Edits build.prop
if [ "$FILESAFE" == 0 ]; then
	log_handler "Checking for conflicting build.prop modules."
	# Checks if any other modules are using a local copy of build.prop
	BUILDMODULE=false
	MODID=$(get_file_value $MODPATH/module.prop "id=")
	for D in $(ls $IMGPATH); do
		if [ $D != "$MODID" ]; then
			if [ -f "$IMGPATH/$D/system/build.prop" ] || [ "$D" == "safetypatcher" ]; then
				NAME=$(get_file_value $IMGPATH/$D/module.prop "name=")
				log_handler "Conflicting build.prop editing in module '$NAME'."
				BUILDMODULE=true
			fi
		fi
	done
	if [ "$BUILDMODULE" == "true" ]; then
		replace_fn BUILDPROPENB 1 0 $LATEFILE
	else
		replace_fn BUILDPROPENB 0 1 $LATEFILE
	fi

	# Copies the stock build.prop to the module. Only if set in propsconf_late.
	if [ "$BUILDPROPENB" == 1 ] && [ "$BUILDEDIT" == 1 ]; then
		log_handler "Stock build.prop copied to module."
		cp -af $MIRRORLOC/build.prop $MODPATH/system/build.prop >> $LOGFILE 2>&1
		
		# Edits the module copy of build.prop
		log_handler "Editing build.prop."
		# ro.build props
		change_prop_file "build"
		# Fingerprint
		if [ "$MODULEFINGERPRINT" ] && [ "$SETFINGERPRINT" == "true" ] && [ "$FINGERPRINTENB" == 1 ]; then
			PRINTSTMP="$(grep "$ORIGFINGERPRINT" $MIRRORLOC/build.prop)"
			for ITEM in $PRINTSTMP; do
				replace_fn $(get_eq_left "$ITEM") $(get_eq_right "$ITEM") $(echo $MODULEFINGERPRINT | sed 's|\_\_.*||') $MODPATH/system/build.prop && log_handler "$(get_eq_left "$ITEM")=$(echo $MODULEFINGERPRINT | sed 's|\_\_.*||')"
			done
		fi
	else
		rm -f $MODPATH/system/build.prop
		log_handler "Build.prop editing disabled."
	fi
else
	rm -f $MODPATH/system/build.prop
	log_handler "Prop file editing disabled. All values ok."
fi

log_script_chk "post-fs-data.sh module script finished.\n\n===================="

# Deletes the post-fs-data control file
rm -f $POSTCHKFILE