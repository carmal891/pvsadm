#!/bin/bash

# Check for the right number of arguments
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <new_version> <brew_tap_repo_url> <formula_file>"
    exit 1
fi

# Ensure the token is available
#if [ -z "$HOMEBREW_UPDATER_TOKEN" ]; then
#    echo "Error: HOMEBREW_UPDATER_TOKEN is not set."
#    exit 1
#fi

# Assign arguments to variables
NEW_VERSION="$1"
BREW_TAP_REPO_URL="$2"
FORMULA_FILE="$3"

#BREW_TAP_REPO_URL="https://github.com/carmal891/homebrew-pvsadm"
FORMULA_PATH="Formula/"

URL_VALUES=(
    "https://github.com/ppc64le-cloud/pvsadm/releases/download/v$NEW_VERSION/pvsadm-darwin-amd64.tar.gz"
    "https://github.com/ppc64le-cloud/pvsadm/releases/download/v$NEW_VERSION/pvsadm-darwin-arm64.tar.gz"
    "https://github.com/ppc64le-cloud/pvsadm/releases/download/v$NEW_VERSION/pvsadm-linux-amd64.tar.gz"
)

# Function to compute SHA256 checksum
compute_sha256() {
    local url="$1"
    local temp_file="$(mktemp)"

    if ! curl -L -o "$temp_file" "$url"; then
        echo "Error: Failed to download $url"
        exit 1
    fi

    # Compute the SHA256 checksum
    local sha256
    sha256=$(shasum -a 256 "$temp_file" | awk '{print $1}')

    # Clean up the temporary file
    rm "$temp_file"

    #For testing purpose echo "SHA256 for $url: $sha256"
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


# Clone the repository with brew formula 
git clone "$BREW_TAP_REPO_URL" brew_tap_repo_temp
if [ $? -ne 0 ]; then
    echo "Error: Failed to clone the repository"
    exit 1
fi

cd brew_tap_repo_temp || { echo "Error: Failed to navigate to brew_tap_repo_temp"; exit 1; }

#Checkout a new branch for the version bump
BRANCH_NAME="bump_formula_v$NEW_VERSION"
git checkout -b "$BRANCH_NAME" || { echo "Error: Failed to create branch $BRANCH_NAME"; exit 1; }

# Navigate to the path containing the formula
cd "$FORMULA_PATH" || { echo "Error: Failed to navigate to $FORMULA_PATH"; exit 1; }

# Update the main version in the formula file
sed -i.bak "s/version \".*\"/version \"$NEW_VERSION\"/" "$FORMULA_FILE"

echo "Updating individual formula to version $NEW_VERSION."

for index in "${!SHAs[@]}"; do
    SHA=${SHAs[$index]}
    echo "$SHA"  

    # Determine the URL pattern based on the index or any logic that helps to identify the platform
    # Assuming you have a corresponding version or URL array that matches SHAs
    URL=${URL_VALUES[$index]}

    if [[ $URL == *"/pvsadm-linux-amd64.tar.gz" ]]; then
        perl -i -pe 's|(https://github.com/ppc64le-cloud/pvsadm/releases/download/v)(\d+\.\d+\.\d+)(/pvsadm-linux-amd64\.tar\.gz)|${1}'${NEW_VERSION}'${3}|g' $FORMULA_FILE
        perl -i -0pe 's|(url "https://github.com/ppc64le-cloud/pvsadm/releases/download/v[0-9]+\.[0-9]+\.[0-9]+/pvsadm-linux-amd64\.tar\.gz"\s*sha256 ")[^"]*(")|${1}'${SHA}'${2}|g' $FORMULA_FILE

    elif [[ $URL == *"/pvsadm-darwin-arm64.tar.gz" ]]; then
        perl -i -pe 's|(https://github.com/ppc64le-cloud/pvsadm/releases/download/v)(\d+\.\d+\.\d+)(/pvsadm-darwin-arm64\.tar\.gz)|${1}'${NEW_VERSION}'${3}|g' $FORMULA_FILE
        perl -i -0pe 's|(url "https://github.com/ppc64le-cloud/pvsadm/releases/download/v[0-9]+\.[0-9]+\.[0-9]+/pvsadm-darwin-arm64\.tar\.gz"\s*sha256 ")[^"]*(")|${1}'${SHA}'${2}|g' $FORMULA_FILE

    elif [[ $URL == *"/pvsadm-darwin-amd64.tar.gz" ]]; then
        perl -i -pe 's|(https://github.com/ppc64le-cloud/pvsadm/releases/download/v)(\d+\.\d+\.\d+)(/pvsadm-darwin-amd64\.tar\.gz)|${1}'${NEW_VERSION}'${3}|g' $FORMULA_FILE
        perl -i -0pe 's|(url "https://github.com/ppc64le-cloud/pvsadm/releases/download/v[0-9]+\.[0-9]+\.[0-9]+/pvsadm-darwin-amd64\.tar\.gz"\s*sha256 ")[^"]*(")|${1}'${SHA}'${2}|g' $FORMULA_FILE

    else
        echo "Warning: Unrecognized URL pattern for SHA: $SHA"
    fi
done

# Below steps to commit, push the changes to the remote tap repository and create PR for review
git add "$FORMULA_FILE"
git commit -m "Update formula to version $NEW_VERSION"
git remote set-url origin https://x-access-token:${GITHUB_TOKEN}@github.com/carmal891/homebrew-pvsadm.git
git push origin "$BRANCH_NAME"
unset GITHUB_TOKEN
gh auth login
gh auth status
sleep 3
if gh pr create --head "$BRANCH_NAME" \
    --title "Updates formula to version $NEW_VERSION" \
    --body "New Release version $NEW_VERSION has been created in pvsadm. Bumping formula version for pvsadm to version $NEW_VERSION."; then
    
    echo "Updated formula to version $NEW_VERSION, pushed changes to $BRANCH_NAME, and created a PR"
else
    echo "There was an error in the PR generation process"
fi