#!/bin/bash

app=$YNH_APP_INSTANCE_NAME
final_path="/var/www/$app"
compose_file="$final_path/docker-compose.yml"

get_setting_or_die() {
	local key=$1
	local value
	value=$(ynh_app_setting_get --app="$app" --key="$key")
	[ -n "$value" ] || ynh_die --message="Missing $key setting"
	echo "$value"
}

render_compose_file() {
	local app_port=$1
	local image=$2
	local nextcloud_base_url=$3
	local nextcloud_share_token=$4
	local nextcloud_metadata_path=$5

	mkdir -p "$final_path"
	cp ../conf/docker-compose.yml "$compose_file"
	ynh_replace_string --match_string="__APP__" --replace_string="$app" --target_file="$compose_file"
	ynh_replace_string --match_string="__PORT__" --replace_string="$app_port" --target_file="$compose_file"
	ynh_replace_string --match_string="__APPDIR__" --replace_string="$final_path" --target_file="$compose_file"
	ynh_replace_string --match_string="__IMAGE__" --replace_string="$image" --target_file="$compose_file"
	ynh_replace_string --match_string="__NEXTCLOUD_BASE_URL__" --replace_string="$nextcloud_base_url" --target_file="$compose_file"
	ynh_replace_string --match_string="__NEXTCLOUD_SHARE_TOKEN__" --replace_string="$nextcloud_share_token" --target_file="$compose_file"
	ynh_replace_string --match_string="__NEXTCLOUD_METADATA_PATH__" --replace_string="$nextcloud_metadata_path" --target_file="$compose_file"
}

compose_pull_up() {
	ynh_exec_warn_less docker compose -f "$compose_file" pull
	ynh_exec_warn_less docker compose -f "$compose_file" up -d
}

compose_down_if_exists() {
	if [ -f "$compose_file" ]; then
		ynh_exec_warn_less docker compose -f "$compose_file" down || true
	fi
}
