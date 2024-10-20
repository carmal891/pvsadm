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
FORMULA_PATH="Formula/"
RELEASES_PATH="https://github.com/ppc64le-cloud/pvsadm/releases/download"

URL_VALUES=(
    "$RELEASES_PATH/v$NEW_VERSION/pvsadm-darwin-amd64.tar.gz"
    "$RELEASES_PATH/v$NEW_VERSION/pvsadm-darwin-arm64.tar.gz"
    "$RELEASES_PATH/v$NEW_VERSION/pvsadm-linux-amd64.tar.gz"
)

# Function to compute SHA256 checksum
compute_sha256() {
    local url="$1"
    local temp_file="$(mktemp)"

    if ! curl -L -o "$temp_file" "$url"; then
        echo "Error: failed to download $url"
        exit 1
    fi
    local sha256
    sha256=$(shasum -a 256 "$temp_file" | awk '{print $1}')
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


# Clone the repository with brew formula and checkout a new branch for pushing updates
git clone "$BREW_TAP_REPO_URL" brew_tap_repo_temp
if [ $? -ne 0 ]; then
    echo "Error: failed to clone the repository"
    exit 1
fi
cd brew_tap_repo_temp || { echo "Error: Failed to navigate to brew_tap_repo_temp"; exit 1; }
BRANCH_NAME="bump_formula_v$NEW_VERSION"


git checkout -b "$BRANCH_NAME" || { echo "Error: Failed to create branch $BRANCH_NAME"; exit 1; }

#Navigate to formula path
cd "$FORMULA_PATH" || { echo "Error: Failed to navigate to $FORMULA_PATH"; exit 1; }

#1. Update the main version in the formula file
if [ ! -f "$FORMULA_FILE" ]; then
    echo "Error: Formula file $FORMULA_FILE not found"
    exit 1
fi
sed -i.bak "s/version \".*\"/version \"$NEW_VERSION\"/" "$FORMULA_FILE"

#2. Update the individual formula and SHA based on OS and arch
echo "Updating individual formula to version $NEW_VERSION."

for index in "${!SHAs[@]}"; do
    SHA=${SHAs[$index]}
    echo "$SHA"  

    URL=${URL_VALUES[$index]}

    if [[ $URL == *"/pvsadm-linux-amd64.tar.gz" ]]; then
        perl -i -pe 's|('${RELEASES_PATH}'/v)(\d+\.\d+\.\d+)(/pvsadm-linux-amd64\.tar\.gz)|${1}'${NEW_VERSION}'${3}|g' $FORMULA_FILE
        perl -i -0pe 's|(url "'${RELEASES_PATH}'/v[0-9]+\.[0-9]+\.[0-9]+/pvsadm-linux-amd64\.tar\.gz"\s*sha256 ")[^"]*(")|${1}'${SHA}'${2}|g' $FORMULA_FILE

    elif [[ $URL == *"/pvsadm-darwin-arm64.tar.gz" ]]; then
        perl -i -pe 's|('${RELEASES_PATH}'/v)(\d+\.\d+\.\d+)(/pvsadm-darwin-arm64\.tar\.gz)|${1}'${NEW_VERSION}'${3}|g' $FORMULA_FILE
        perl -i -0pe 's|(url "'${RELEASES_PATH}'/v[0-9]+\.[0-9]+\.[0-9]+/pvsadm-darwin-arm64\.tar\.gz"\s*sha256 ")[^"]*(")|${1}'${SHA}'${2}|g' $FORMULA_FILE

    elif [[ $URL == *"/pvsadm-darwin-amd64.tar.gz" ]]; then
        perl -i -pe 's|('${RELEASES_PATH}'/v)(\d+\.\d+\.\d+)(/pvsadm-darwin-amd64\.tar\.gz)|${1}'${NEW_VERSION}'${3}|g' $FORMULA_FILE
        perl -i -0pe 's|(url "'${RELEASES_PATH}'/v[0-9]+\.[0-9]+\.[0-9]+/pvsadm-darwin-amd64\.tar\.gz"\s*sha256 ")[^"]*(")|${1}'${SHA}'${2}|g' $FORMULA_FILE

    else
        echo "Warning: Unrecognized URL pattern for SHA: $SHA"
    fi
done


#commit, push the changes to the remote tap repository and create PR for review
if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: GITHUB_TOKEN is not set"
    exit 1
fi

if git ls-remote --exit-code --heads origin "$BRANCH_NAME"; then
    echo "Error: The branch '$BRANCH_NAME' already exists on the remote. Please create a new branch."
    exit 1
fi

git add "$FORMULA_FILE"
git commit -m "Update formula to version $NEW_VERSION"
git remote set-url origin https://x-access-token:${GITHUB_TOKEN}@${BREW_TAP_REPO_URL#https://}

if ! git push origin "$BRANCH_NAME"; then
    echo "Error: Failed to push branch $BRANCH_NAME"
    exit 1
fi

unset GITHUB_TOKEN

if gh pr create --head "$BRANCH_NAME" \
    --title "Updates formula to version $NEW_VERSION" \
    --body "New Release version $NEW_VERSION has been created in pvsadm. Bumping formula version for pvsadm to version $NEW_VERSION."; then

    echo "Updated formula to version $NEW_VERSION, pushed changes to $BRANCH_NAME, and created a PR"
else
    echo "Error: failed to create PR"
    exit 1 
fi