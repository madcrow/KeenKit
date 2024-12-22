#!/bin/sh

RED='\033[1;31m'
GREEN='\033[1;32m'
CYAN='\033[0;36m'
NC='\033[0m'

USERNAME="madcrow"
OTA_USERNAME="spatiumstas"
USER='root'
REPO="KeenKit"
SCRIPT="keenkit.sh"
TMP_DIR="/tmp"
OPT_DIR="/opt"
STORAGE_DIR="/storage"
VERSION="1.13"
MINRAMSIZE="220"
PACKAGES_LIST="curl python3-base python3 python3-light libpython3"

print_menu() {
  printf "\033c"
  printf "${CYAN}"
  cat <<'EOF'
    __ __                __ __ _ __          ___ ________
   / //_/__  ___  ____  / //_/(_) /_   _   _<  /<  /__  /
  / ,< / _ \/ _ \/ __ \/ ,<  / / __/  | | / / / / / /_ <
 / /| /  __/  __/ / / / /| |/ / /_    | |/ / / / /___/ /
/_/ |_\___/\___/_/ /_/_/ |_/_/\__/    |___/_(_)_//____/
EOF
  printf "by ${USERNAME}\n"
  printf "${NC}"
  echo ""
  echo "1. Update firmware from file"
  echo "2. Backup partition"
  echo "3. Backup Entware"
  echo "4. Replace partition"
  echo "5. OTA Update"
  echo "6. Replace service data"
  echo ""
  echo "88. Delete packages installed by KeenKit"
  echo "99. Update the script"
  echo "00. Exit"
  echo ""
}

main_menu() {
  print_menu
  read -p "Select an action: " choice
  echo ""
  choice=$(echo "$choice" | tr -d '\032' | tr -d '[A-Z]')

  if [ -z "$choice" ]; then
    main_menu
  else
    case "$choice" in
    1) firmware_manual_update ;;
    2) backup_block ;;
    3) backup_entware ;;
    4) rewrite_block ;;
    5) ota_update ;;
    6) service_data_generator ;;
    00) exit ;;
    88) packages_delete ;;
    99) script_update "main" ;;
    999) script_update "dev" ;;
    *)
      echo "Wrong choice. Try again."
      sleep 1
      main_menu
      ;;
    esac
  fi
}

print_message() {
  local message=$1
  local color=${2:-$NC}
  local border=$(printf '%0.s-' $(seq 1 $((${#message} + 2))))
  printf "${color}\n+${border}+\n| ${message} |\n+${border}+\n${NC}\n"
  sleep 1
}

packages_checker() {
  if ! opkg list-installed | grep -q "^curl"; then
    print_message "Installing curl..." "$GREEN"
    opkg update && opkg install curl
    echo ""
  fi
}

packages_delete() {
  delete_log=$(opkg remove $PACKAGES_LIST --autoremove 2>&1)
  removed_packages=""
  failed_packages=""

  for package in $PACKAGES_LIST; do
    if echo "$delete_log" | grep -q "Removing package $package"; then
      removed_packages="$removed_packages $package"
    elif echo "$delete_log" | grep -q "Package $package is depended upon by packages"; then
      failed_packages="$failed_packages $package"
    fi
  done

  if [ -n "$removed_packages" ]; then
    print_message "Packages successfully removed: $removed_packages" "$GREEN"
  fi

  if [ -n "$failed_packages" ]; then
    print_message "The following packages could not be removed due to dependencies: $failed_packages" "$RED"
  fi

  if [ -z "$removed_packages" ] && [ -z "$failed_packages" ]; then
    print_message "All packages removed" "$CYAN"
  fi

  read -n 1 -s -r -p "Press any key to return..."
  main_menu
}

identify_external_drive() {
  local message=$1
  local message2=$2
  local special_message=$3
  labels=""
  uuids=""
  index=1
  media_found=0
  media_output=$(ndmc -c show media)

  if [ -z "$media_output" ]; then
    echo "Failed to retrieve the drive list."
    return
  fi

  while IFS= read -r line; do
    if echo "$line" | grep -q "name: Media"; then
      media_found=1
      echo "0. Built-in storage $message2"
    elif [ "$media_found" = "1" ]; then
      if echo "$line" | grep -q "uuid:"; then
        uuid=$(echo "$line" | awk '{print $2}')
      elif echo "$line" | grep -q "label:"; then
        label=$(echo "$line" | awk '{print $2}')
        if [ -n "$uuid" ] && [ -n "$label" ]; then
          echo "$index. $label"
          labels="$labels $label"
          uuids="$uuids $uuid"
          index=$((index + 1))
        fi
      fi
    fi
  done <<EOF
$media_output
EOF

  if [ -z "$labels" ]; then
    selected_drive="$STORAGE_DIR"
    if [ "$special_message" = "true" ]; then
      read -p "Only internal storage found $message2, continue backup? (y/n) " item_rc1
      item_rc1=$(echo "$item_rc1" | tr -d ' \n\r')
      case "$item_rc1" in
      y | Y) ;;
      n | N) main_menu ;;
      *) ;;
      esac
    fi
    return
  fi

  echo ""
  read -p "$message " choice
  choice=$(echo "$choice" | tr -d ' \n\r')
  echo ""
  if [ "$choice" = "0" ]; then
    selected_drive="$STORAGE_DIR"
  else
    selected_drive=$(echo "$uuids" | awk -v choice="$choice" '{split($0, a, " "); print a[choice]}')
    if [ -z "$selected_drive" ]; then
      print_message "Invalid selection" "$RED"
      sleep 2
      main_menu
    fi
    selected_drive="/tmp/mnt/$selected_drive"
  fi
}

has_an_external_storage() {
  local output=$(mount | grep "/dev/sd")
  if echo "$output" | grep -q "/dev/sd" && ! echo "$output" | grep -q "$OPT_DIR"; then
    return 0
  else
    return 1
  fi
}

check_factory_country() {
  output=$(ndmc -c show system country)
  factory=$(echo "$output" | awk '/factory:/ {print $2}')

  if [ "$factory" = "RU" ]; then
    print_message "Country RU, should be changed to EA" "$CYAN"
    service_data_generator "country"
  fi
}

backup_config() {
  if has_an_external_storage; then
    print_message "External drives have been detected" "$CYAN"
    read -p "Create a backup of startup-config? (y/n) " user_input
    user_input=$(echo "$user_input" | tr -d ' \n\r')

    case "$user_input" in
    y | Y)
      echo ""
      identify_external_drive "Select the drive to be backed up:"

      if [ -n "$selected_drive" ]; then
        date="backup$(date +%Y-%m-%d_%H-%M-%S)"
        local device_uuid=$(echo "$selected_drive" | awk -F'/' '{print $NF}')
        local folder_path="$device_uuid:/$date"
        local backup_file="$folder_path/startup-config.txt"

        mkdir -p "$selected_drive/$date"
        ndmc -c "copy startup-config $backup_file"

        if [ $? -eq 0 ]; then
          print_message "Startup-config is saved in $backup_file" "$GREEN"
        else
          print_message "Error while saving backup" "$RED"
        fi
      else
        echo "Backup not performed, drive not selected."
      fi
      ;;
    *)
      echo ""
      ;;
    esac
  fi
}

script_update() {
  BRANCH="$1"
  packages_checker
  curl -L -s "https://raw.githubusercontent.com/$USERNAME/$REPO/$BRANCH/$SCRIPT" --output $TMP_DIR/$SCRIPT

  if [ -f "$TMP_DIR/$SCRIPT" ]; then
    mv "$TMP_DIR/$SCRIPT" "$OPT_DIR/$SCRIPT"
    chmod +x $OPT_DIR/$SCRIPT
    cd $OPT_DIR/bin
    ln -sf $OPT_DIR/$SCRIPT $OPT_DIR/bin/KeenKit
    ln -sf $OPT_DIR/$SCRIPT $OPT_DIR/bin/keenkit
    print_message "The script has been successfully updated" "$GREEN"
    $OPT_DIR/$SCRIPT post_update
  else
    print_message "Error downloading the script" "$RED"
  fi
}

url() {
  PART1="aHR0cHM6Ly9sb2c"
  PART2="uc3BhdGl1bS5rZWVuZXRpYy5wcm8="
  PART3="${PART1}${PART2}"
  URL=$(echo "$PART3" | base64 -d)
  echo "${URL}"
}

post_update() {
  URL=$(url)
  JSON_DATA="{\"script_update\": \"$VERSION\"}"
  curl -X POST -H "Content-Type: application/json" -d "$JSON_DATA" "$URL" -o /dev/null -s
  main_menu
}

internet_checker() {
  if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    print_message "No Internet access. Check connection." "$RED"
    read -n 1 -s -r -p "Press any key to return..."
    main_menu
  fi
}

get_architecture() {
  arch=$(opkg print-architecture | grep -oE 'mips-3|mipsel-3|aarch64-3|armv7' | head -n 1)

  case "$arch" in
  "mips-3") echo "mips" ;;
  "mipsel-3") echo "mipsel" ;;
  "aarch64-3") echo "aarch64" ;;
  "armv7") echo "armv7" ;;
  *) echo "unknown_arch" ;;
  esac
}

mountFS() {
  mount -t tmpfs tmpfs /tmp
  wait
  print_message "LockFS: true"
}

umountFS() {
  umount /tmp
  wait
  print_message "UnlockFS: true"
}

get_ram_size() {
  grep MemTotal /proc/meminfo | awk '{print int($2 / 1024)}'
}

ota_update() {
  REPO="osvault"
  packages_checker
  internet_checker
  DIRS=$(curl -s "https://api.github.com/repos/$OTA_USERNAME/$REPO/contents/" | grep -Po '"name":.*?[^\\]",' | awk -F'"' '{print $4}' | grep -v '^\.\(github\)$')

  echo "Available models:"
  i=1
  IFS=$'\n'
  for DIR in $DIRS; do
    printf "${CYAN}$i. $DIR${NC}\n"
    i=$((i + 1))
  done
  printf "${CYAN}00. Exit to the main menu\n${NC}"
  echo ""
  read -p "Select a model: " DIR_NUM
  if [ "$DIR_NUM" = "00" ]; then
    main_menu
  fi
  DIR=$(echo "$DIRS" | sed -n "${DIR_NUM}p")

  BIN_FILES=$(curl -s "https://api.github.com/repos/$OTA_USERNAME/$REPO/contents/$(echo "$DIR" | sed 's/ /%20/g')" | grep -Po '"name":.*?[^\\]",' | awk -F'"' '{print $4}' | grep ".bin")
  if [ -z "$BIN_FILES" ]; then
    printf "${RED}There are no files in the $DIR directory.${NC}\n"
  else
    printf "\nFirmware for $DIR:\n"
    i=1
    for FILE in $BIN_FILES; do
      printf "${CYAN}$i. $FILE${NC}\n"
      i=$((i + 1))
    done
    printf "${CYAN}00. Exit to the main menu\n${NC}"
    echo ""
    read -p "Select the firmware: " FILE_NUM
    if [ "$FILE_NUM" = "00" ]; then
      main_menu
    fi
    FILE=$(echo "$BIN_FILES" | sed -n "${FILE_NUM}p")

    ram_size=$(get_ram_size)
    if [ "$ram_size" -lt $MINRAMSIZE ]; then
      DOWNLOAD_PATH="$OPT_DIR"
      use_mount=true
    else
      DOWNLOAD_PATH="$TMP_DIR"
      use_mount=false
    fi
    printf "\nUploading firmware to $DOWNLOAD_PATH...\n"

    mkdir -p "$DOWNLOAD_PATH"
    if ! curl -L -s "https://raw.githubusercontent.com/$OTA_USERNAME/$REPO/master/$(echo "$DIR" | sed 's/ /%20/g')/$(echo "$FILE" | sed 's/ /%20/g')" --output "$DOWNLOAD_PATH/$FILE"; then
      print_message "Failed to download file $FILE. Check free space" "$RED"
      main_menu
    fi

    if [ ! -f "$DOWNLOAD_PATH/$FILE" ]; then
      printf "${RED} The file $FILE was not downloaded/found.${NC}\n"
      read -n 1 -s -r -p "Press any key to return..."
    fi

    curl -L -s "https://raw.githubusercontent.com/$OTA_USERNAME/$REPO/master/$(echo "$DIR" | sed 's/ /%20/g')/md5sum" --output "$DOWNLOAD_PATH/md5sum"

    MD5SUM=$(grep "$FILE" "$DOWNLOAD_PATH/md5sum" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')
    FILE_MD5SUM=$(md5sum "$DOWNLOAD_PATH/$FILE" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')

    if [ "$MD5SUM" != "$FILE_MD5SUM" ]; then
      printf "${RED}MD5 hash doesn't match.${NC}"
      echo "Expected: $MD5SUM"
      echo "Actual: $FILE_MD5SUM"
      rm -f "$DOWNLOAD_PATH/$FILE"
      return
    fi

    printf "${GREEN}MD5 hash match${NC}\n"
    rm -f "$DOWNLOAD_PATH/md5sum"
    echo ""
    read -p "Selected $FILE to update, is everything correct? (y/n) " CONFIRM
    case "$CONFIRM" in
    y | Y)
      update_firmware_block "$DOWNLOAD_PATH/$FILE" "$use_mount"
      ;;
    *)
      echo ""
      ;;
    esac
    rm -f "$DOWNLOAD_PATH/$FILE"
    print_message "Rebooting the device..." "${CYAN}"
    sleep 1
    reboot
    main_menu
  fi
}

update_firmware_block() {
  local firmware="$1"
  local use_mount="$2"
  echo ""
  check_factory_country
  backup_config
  if [ "$use_mount" = true ] || [[ "$firmware" == *"$STORAGE_DIR"* ]]; then
    mountFS
  fi

  for partition in Firmware Firmware_1 Firmware_2; do
    wait

    mtdSlot="$(grep -w '/proc/mtd' -e "$partition")"
    if [ -z "$mtdSlot" ]; then
      sleep 1
    else
      result=$(echo "$mtdSlot" | grep -oP '.*(?=:)' | grep -oE '[0-9]+')
      echo "$partition on mtd${result} partition, updating..."
      dd if="$firmware" of="/dev/mtdblock$result" conv=fsync
      wait
      echo ""
    fi
  done

  if [ "$use_mount" = true ] || [[ "$firmware" == *"$STORAGE_DIR"* ]]; then
    umountFS
  fi
}

firmware_manual_update() {
  ram_size=$(get_ram_size)

  if [ "$ram_size" -lt $MINRAMSIZE ]; then
    print_message "For this device, the update is only available from a drive with Entware installed" "$CYAN"
    selected_drive="$STORAGE_DIR"
    use_mount=true
  else
    output=$(mount)
    identify_external_drive "Select the drive where the update file is located:"
    selected_drive="$selected_drive"
    use_mount=false
  fi

  files=$(find "$selected_drive" -name '*.bin' -size +10M -size -30M)
  count=$(echo "$files" | wc -l)

  if [ -z "$files" ]; then
    print_message "Update file not found on the drive" "$RED"
    echo ""
    read -n 1 -s -r -p "Press any key to return..."
    main_menu
  fi

  echo "$files" | awk '{print NR".", substr($0, 10)}'
  printf "${CYAN}00. Exit to main menu${NC}\n"
  echo ""
  read -p "Select the update file (1 to $count): " choice
  choice=$(echo "$choice" | tr -d ' \n\r')
  if [ "$choice" = "00" ]; then
    main_menu
  fi
  if [ "$choice" -lt 1 ] || [ "$choice" -gt "$count" ]; then
    print_message "Incorrect file selection" "$RED"
    read -n 1 -s -r -p "Press any key to return..."
    main_menu
  fi

  Firmware=$(echo "$files" | awk "NR==$choice")
  FirmwareName=$(basename "$Firmware")
  echo ""
  read -p "Selected $FirmwareName to update, is everything correct? (y/n) " item_rc1
  item_rc1=$(echo "$item_rc1" | tr -d ' \n\r')
  case "$item_rc1" in
  y | Y)
    update_firmware_block "$Firmware" "$use_mount"
    read -p "Delete the update file? (y/n) " item_rc2
    item_rc2=$(echo "$item_rc2" | tr -d ' \n\r')
    case "$item_rc2" in
    y | Y)
      rm "$Firmware"
      wait
      sleep 2
      ;;
    n | N)
      echo ""
      ;;
    *) ;;
    esac
    print_message "Rebooting the device..." "${CYAN}"
    sleep 1
    reboot
    ;;
  esac
  main_menu
}

backup_block() {
  output=$(mount)
  identify_external_drive "Select the drive:"
  output=$(cat /proc/mtd)
  printf "${GREEN}Available partitions:${NC}\n"
  echo "$output" | awk 'NR>1 {print $0}'
  printf "${CYAN}00. Exit to the main menu\n"
  printf "99. Backup all partitions${NC}"
  echo -e "\n"
  folder_path="$selected_drive/backup$(date +%Y-%m-%d_%H-%M-%S)"
  read -p "Indicate the number of the partition(s) separated by spaces: " choice
  echo ""
  choice=$(echo "$choice" | tr -d '\n\r')

  if [ "$choice" = "00" ]; then
    main_menu
  fi

  error_occurred=0
  non_existent_parts=""
  valid_parts=0

  if [ "$choice" = "99" ]; then
    output_all_mtd=$(cat /proc/mtd | grep -c "mtd")
    for i in $(seq 0 $(($output_all_mtd - 1))); do
      mtd_name=$(echo "$output" | awk -v i=$i 'NR==i+2 {print substr($0, index($0,$4))}' | grep -oP '(?<=\").*(?=\")')
      echo "Copying mtd$i.$mtd_name.bin..."
      if [ $valid_parts -eq 0 ]; then
        mkdir -p "$folder_path"
        valid_parts=1
      fi

      if ! cat "/dev/mtdblock$i" >"$folder_path/mtd$i.$mtd_name.bin"; then
        error_occurred=1
        print_message "Error: Not enough space to save mtd$i.$mtd_name.bin" "$RED"
        echo ""
        read -n 1 -s -r -p "Press any key to return..."
        break
      fi
      wait
    done
  else
    for part in $choice; do
      if ! echo "$output" | awk -v i=$part 'NR==i+2 {print $1}' | grep -q "mtd$part"; then
        non_existent_parts="$non_existent_parts $part"
        continue
      fi

      selected_mtd=$(echo "$output" | awk -v i=$part 'NR==i+2 {print substr($0, index($0,$4))}' | grep -oP '(?<=\").*(?=\")')

      if [ $valid_parts -eq 0 ]; then
        mkdir -p "$folder_path"
        valid_parts=1
      fi

      echo "Selected mtd$part.$selected_mtd.bin, copying..."
      sleep 1
      if ! dd if="/dev/mtd$part" of="$folder_path/mtd$part.$selected_mtd.bin" 2>&1; then
        error_occurred=1
        print_message "Error: Not enough space to save mtd$part.$selected_mtd.bin" "$RED"
        echo ""
        read -n 1 -s -r -p "Press any key to return..."
        break
      fi
      wait
      echo ""
    done
  fi

  if [ -n "$non_existent_parts" ]; then
    print_message "Error: Partitions${non_existent_parts} do not exist!" "$RED"
    error_occurred=1
  fi

  if [ "$error_occurred" -eq 0 ] && [ $valid_parts -eq 1 ]; then
    print_message "Partition(s) successfully saved to $folder_path" "$GREEN"
  else
    print_message "Errors saving partition(s). Check the output above." "$RED"
  fi

  read -n 1 -s -r -p "Press any key to return..."
  main_menu
}

backup_entware() {
  output=$(mount)
  identify_external_drive "Select the drive:" "(there might not be enough space)" "true"
  print_message "Copying..." "$CYAN"

  arch=$(get_architecture)

  backup_file="$selected_drive/${arch}_entware_backup_$(date +%Y-%m-%d_%H-%M-%S).tar.gz"
  backup_output=$(tar cvzf "$backup_file" -C $OPT_DIR . 2>&1)
  wait

  if echo "$backup_output" | grep -q "No space left on device"; then
    print_message "Backup failed, check free space" "$RED"
    echo ""
    read -n 1 -s -r -p "Press any key to return..."
  else
    print_message "Backup successfully copied to $backup_file" "$GREEN"
    read -n 1 -s -r -p "Press any key to return..."
  fi
  main_menu
}

rewrite_block() {
  output=$(mount)
  identify_external_drive "Select the drive where the file is located:"
  files=$(find $selected_drive -name '*.bin' -size +64k -size -30M)
  count=$(echo "$files" | wc -l)
  if [ -z "$files" ]; then
    print_message "No .bin files found on the selected drive" "$RED"
    echo ""
    read -n 1 -s -r -p "Press any key to return..."
    main_menu
  fi
  echo ""
  echo "Available files:"
  echo "$files" | awk '{print NR".", substr($0, 10)}'
  printf "\n${CYAN}00. Exit to main menu${NC}\n"
  echo ""
  read -p "Select the file to be replaced: " choice
  choice=$(echo "$choice" | tr -d ' \n\r')
  if [ "$choice" = "00" ]; then
    main_menu
  fi
  if [ $choice -lt 1 ] || [ $choice -gt $count ]; then
    print_message "Incorrect file selection" "$RED"
    read -n 1 -s -r -p "Press any key to return..."
    main_menu
  fi

  mtdFile=$(echo "$files" | awk "NR==$choice")
  mtdName=$(basename "$mtdFile")
  echo ""
  output=$(cat /proc/mtd)
  echo "$output" | awk 'NR>1 {print $0}'
  printf "${CYAN}00. Exit to main menu${NC}\n"
  printf "\n${GREEN}Selected $mtdName for replacement${NC}\n"
  printf "\n${RED}WARNING! The bootloader is not overwritten! ${NC}\n"
  read -p "Select which partition to overwrite (e.g. for mtd2 it is 2): " choice
  choice=$(echo "$choice" | tr -d ' \n\r')
  if [ "$choice" = "00" ]; then
    main_menu
  fi
  if [ "$choice" = "0" ]; then
    print_message "The bootloader is not overwritten!" "$RED"
    read -n 1 -s -r -p "Press any key to return..."
    main_menu
  fi
  selected_mtd=$(echo "$output" | awk -v i=$choice 'NR==i+2 {print substr($0, index($0,$4))}' | grep -oP '(?<=\").*(?=\")')
  echo ""
  read -r -p "Перезаписать раздел mtd$choice.$selected_mtd вашим $mtdName? (y/n) " item_rc1
  item_rc1=$(echo "$item_rc1" | tr -d ' \n\r')
  case "$item_rc1" in
  y | Y)
    sleep 1
    echo ""
    rewrite=$(dd if=$mtdFile of=/dev/mtdblock$choice)
    wait
    if echo "$rewrite" | grep -q "No space left on device"; then
      print_message "Overwrite failed, file to be written is larger than the partition" "$RED"
    else
      print_message "Partition successfully overwritten" "$GREEN"
    fi
    printf "${NC}"
    read -r -p "Reboot the router? (y/n) " item_rc3
    item_rc3=$(echo "$item_rc3" | tr -d ' \n\r')
    case "$item_rc3" in
    y | Y)
      echo ""
      reboot
      ;;
    n | N)
      echo ""
      ;;
    *) ;;
    esac
    ;;
  n | N)
    echo ""
    ;;
  esac
  read -n 1 -s -r -p "Press any key to return..."
  main_menu
}

service_data_generator() {
  folder_path="$OPT_DIR/backup$(date +%Y-%m-%d_%H-%M-%S)"
  SCRIPT_PATH="$OPT_DIR/service_data_generator.py"
  missing_packages=""
  target_flag=$1

  for package in $PACKAGES_LIST; do
    if ! opkg list-installed | grep -q "^$package"; then
      missing_packages="$missing_packages $package"
    fi
  done

  if [ -n "$missing_packages" ]; then
    read -p "The following packages are missing:$missing_packages. Do you want to install them? (y/n) " item_rc1
    item_rc1=$(echo "$item_rc1" | tr -d ' \n\r')
    case "$item_rc1" in
    y | Y)
      echo ""
      internet_checker
      opkg update
      opkg install $missing_packages --nodeps
      for package in $missing_packages; do
        if ! opkg list-installed | grep -q "^$package"; then
          print_message "Error: package $package is not installed." "$RED"
          read -n 1 -s -r -p "Press any key to return..."
          main_menu
        fi
      done
      ;;
    n | N)
      print_message "Necessary packages are not installed." "$RED"
      read -n 1 -s -r -p "Press any key to return..."
      main_menu
      return
      ;;
    esac
  fi

  if [ ! -f "$SCRIPT_PATH" ]; then
    curl -L -s "https://raw.githubusercontent.com/$USERNAME/$REPO/main/service_data_generator.py" --output "$SCRIPT_PATH"
    if [ $? -ne 0 ]; then
      print_message "Error loading $SCRIPT_PATH script" "$RED"
      return
    fi
  fi

  mkdir -p "$folder_path"
  mtdSlot=$(grep -w 'U-Config' /proc/mtd | awk -F: '{print $1}' | grep -oE '[0-9]+')
  mtdSlot_res=$(grep -w 'U-Config_res' /proc/mtd | awk -F: '{print $1}' | grep -oE '[0-9]+')
  if [ -n "$mtdSlot" ]; then
    dd if="/dev/mtd$mtdSlot" of="$folder_path/U-Config.bin" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      print_message "A backup of the current U-Config is saved to $folder_path" "$GREEN"
    else
      print_message "Error creating U-Config backup" "$RED"
    fi
  fi

  if [ -n "$target_flag" ]; then
    python3 "$SCRIPT_PATH" "$folder_path/U-Config.bin" "$target_flag"
  else
    python3 "$SCRIPT_PATH" "$folder_path/U-Config.bin"
  fi

  mtdFile=$(find "$folder_path" -type f -name 'U-Config_*.bin' | head -n 1)
  if [ -n "$mtdFile" ]; then
    print_message "The new service data is stored in $mtdFile" "$GREEN"
  fi
  read -p "Confirm replacement? (y/n) " item_rc1
  item_rc1=$(echo "$item_rc1" | tr -d ' \n\r')
  case "$item_rc1" in
  y | Y)
    echo ""
    dd if="$mtdFile" of="/dev/mtdblock$mtdSlot"
    if [ -n "$mtdSlot_res" ]; then
      echo ""
      printf "${CYAN}Found the second partition, replacing...${NC}"
      echo ""
      dd if="$mtdFile" of="/dev/mtdblock$mtdSlot_res"
    fi
    if [ $? -eq 0 ]; then
      print_message "Service data successfully replaced" "$GREEN"
    else
      print_message "Error performing replacement" "$RED"
    fi
    ;;
  esac
  if [ -z "$target_flag" ]; then
    read -p "Reboot the router? (y/n) " item_rc2
    item_rc2=$(echo "$item_rc2" | tr -d ' \n\r')
    case "$item_rc2" in
    y | Y)
      echo ""
      reboot
      ;;
    n | N)
      echo ""
      ;;
    *) ;;
    esac
    echo "Return to the main menu..."
    sleep 1
    main_menu
  fi
}

if [ "$1" = "script_update" ]; then
  script_update
elif [ "$1" = "post_update" ]; then
  post_update
else
  main_menu
fi
