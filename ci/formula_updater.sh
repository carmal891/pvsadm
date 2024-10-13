#!/bin/bash

# Check for the right number of arguments
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <new_version> <formula_file>"
    exit 1
fi

# Ensure the token is available
if [ -z "$HOMEBREW_UPDATER_TOKEN" ]; then
    echo "Error: HOMEBREW_UPDATER_TOKEN is not set."
    exit 1
fi

# Assign arguments to variables
NEW_VERSION="$1"
FORMULA_FILE="$2"

REPO_B_URL="https://github.com/carmal891/homebrew-pvsadm"
FORMULA_PATH="Formula/"

# Define URLs for the new version using indexed arrays
URLS=("darwin-amd64" "darwin-arm64" "linux-amd64")
URL_VALUES=(
    "https://github.com/ppc64le-cloud/pvsadm/releases/download/v$NEW_VERSION/pvsadm-darwin-amd64.tar.gz"
    "https://github.com/ppc64le-cloud/pvsadm/releases/download/v$NEW_VERSION/pvsadm-darwin-arm64.tar.gz"
    "https://github.com/ppc64le-cloud/pvsadm/releases/download/v$NEW_VERSION/pvsadm-linux-amd64.tar.gz"
)

# Function to compute SHA256 checksum
compute_sha256() {
    local url="$1"
    #echo "Computing SHA for $url ..."
    local temp_file="$(mktemp)"

    # Download the file
    if ! curl -L -o "$temp_file" "$url"; then
        echo "Error: Failed to download $url"
        exit 1
    fi

    # Compute the SHA256 checksum
    local sha256
    sha256=$(shasum -a 256 "$temp_file" | awk '{print $1}')

    # Clean up the temporary file
    rm "$temp_file"

    # Print the SHA256 checksum
    #echo "SHA256 for $url: $sha256"
    echo "$sha256"
    
}

# Compute SHA256 checksums for the new version
SHAs=()
for url in "${URL_VALUES[@]}"; do
    SHA=$(compute_sha256 "$url")
    if [ -z "$SHA" ]; then
        echo "Error: SHA256 could not be computed for $url"
        exit 1
    fi
    SHAs+=("$SHA")

    echo $SHA

    sleep 1

done


# Clone the repository B
git clone "$REPO_B_URL" repo_B_temp
if [ $? -ne 0 ]; then
    echo "Error: Failed to clone the repository"
    exit 1
fi


# Navigate to the cloned repository
cd repo_B_temp || { echo "Error: Failed to navigate to repo_B_temp"; exit 1; }

# Create a new branch for the version bump
BRANCH_NAME="bump_formula_v$NEW_VERSION"
git checkout -b "$BRANCH_NAME" || { echo "Error: Failed to create branch $BRANCH_NAME"; exit 1; }

# Navigate to the path containing the formula
cd "$FORMULA_PATH" || { echo "Error: Failed to navigate to $FORMULA_PATH"; exit 1; }


# Update the main version in the formula file
sed -i.bak "s/version \".*\"/version \"$NEW_VERSION\"/" "$FORMULA_FILE"

echo "Updating individual formula to version $NEW_VERSION."

for index in "${!SHAs[@]}"; do
    # Get the current SHA value
    SHA=${SHAs[$index]}
    echo "$SHA"  

    # Determine the URL pattern based on the index or any logic that helps to identify the platform
    # Assuming you have a corresponding version or URL array that matches SHAs
    URL=${URL_VALUES[$index]}  # Assuming this contains the URLs for corresponding SHAs

    if [[ $URL == *"/pvsadm-linux-amd64.tar.gz" ]]; then
        # Handle Linux AMD64
        perl -i -pe 's|(https://github.com/ppc64le-cloud/pvsadm/releases/download/v)(\d+\.\d+\.\d+)(/pvsadm-linux-amd64\.tar\.gz)|${1}'${NEW_VERSION}'${3}|g' $FORMULA_FILE
        perl -i -0pe 's|(url "https://github.com/ppc64le-cloud/pvsadm/releases/download/v[0-9]+\.[0-9]+\.[0-9]+/pvsadm-linux-amd64\.tar\.gz"\s*sha256 ")[^"]*(")|${1}'${SHA}'${2}|g' $FORMULA_FILE

    elif [[ $URL == *"/pvsadm-darwin-arm64.tar.gz" ]]; then
        # Handle Darwin ARM64
        perl -i -pe 's|(https://github.com/ppc64le-cloud/pvsadm/releases/download/v)(\d+\.\d+\.\d+)(/pvsadm-darwin-arm64\.tar\.gz)|${1}'${NEW_VERSION}'${3}|g' $FORMULA_FILE
        perl -i -0pe 's|(url "https://github.com/ppc64le-cloud/pvsadm/releases/download/v[0-9]+\.[0-9]+\.[0-9]+/pvsadm-darwin-arm64\.tar\.gz"\s*sha256 ")[^"]*(")|${1}'${SHA}'${2}|g' $FORMULA_FILE

    elif [[ $URL == *"/pvsadm-darwin-amd64.tar.gz" ]]; then
        # Handle Darwin AMD64
        perl -i -pe 's|(https://github.com/ppc64le-cloud/pvsadm/releases/download/v)(\d+\.\d+\.\d+)(/pvsadm-darwin-amd64\.tar\.gz)|${1}'${NEW_VERSION}'${3}|g' $FORMULA_FILE
        perl -i -0pe 's|(url "https://github.com/ppc64le-cloud/pvsadm/releases/download/v[0-9]+\.[0-9]+\.[0-9]+/pvsadm-darwin-amd64\.tar\.gz"\s*sha256 ")[^"]*(")|${1}'${SHA}'${2}|g' $FORMULA_FILE

    else
        echo "Warning: Unrecognized URL pattern for SHA: $SHA"
    fi
done

# Commit the changes
git add "$FORMULA_FILE"
git commit -m "Update formula to version $NEW_VERSION"

git remote set-url origin https://x-access-token:${HOMEBREW_UPDATER_TOKEN}@github.com/carmal891/homebrew-pvsadm.git


# Push the changes to the remote repository
git push origin "$BRANCH_NAME"

gh auth login --with-token <<< "${HOMEBREW_UPDATER_TOKEN}"

# Create a pull request to the master branch
gh pr create --base master --head "$BRANCH_NAME" --title "Update formula to version $NEW_VERSION" --body "This PR updates the formula for pvsadm to version $NEW_VERSION."

echo "Updated formula to version $NEW_VERSION, pushed changes to $BRANCH_NAME, and created a PR to master."