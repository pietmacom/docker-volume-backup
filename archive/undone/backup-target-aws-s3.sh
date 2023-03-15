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

AWS_S3_BUCKET_NAME="${AWS_S3_BUCKET_NAME:-}"
AWS_EXTRA_ARGS="${AWS_EXTRA_ARGS:-}"

function _backup() {
	if [[ -z "$AWS_S3_BUCKET_NAME" ]]; then echo "AWS_S3_BUCKET_NAME not set" && exit 1; fi
	
	_info "Uploading backup to S3"
	echo "Will upload to bucket \"$AWS_S3_BUCKET_NAME\""
	_awsConfigure
	aws $AWS_EXTRA_ARGS s3 cp --only-show-errors "$_backupFullFilename" "s3://$AWS_S3_BUCKET_NAME/"
}
