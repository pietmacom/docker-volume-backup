function _awsConfigure() {
	mkdir -p .aws
	cat <<EOF > .aws/credentials
[default]
aws_access_key_id = ${AWS_ACCESS_KEY_ID}
aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}
EOF

	if [ ! -z "$AWS_DEFAULT_REGION" ]; then
		cat <<EOF > .aws/config
[default]
region = ${AWS_DEFAULT_REGION}
EOF
	fi
}

AWS_GLACIER_VAULT_NAME="${AWS_GLACIER_VAULT_NAME:-}"
AWS_EXTRA_ARGS="${AWS_EXTRA_ARGS:-}"

function _backup() {	
	if [[ -z "$AWS_GLACIER_VAULT_NAME" ]]; then echo "AWS_GLACIER_VAULT_NAME not set" && exit 1; fi
	
	_info "Uploading backup to GLACIER"
	echo "Will upload to vault \"$AWS_GLACIER_VAULT_NAME\""
	_awsConfigure
	aws $AWS_EXTRA_ARGS glacier upload-archive --account-id - --vault-name "$AWS_GLACIER_VAULT_NAME" --body "$_backupFullFilename"
}
