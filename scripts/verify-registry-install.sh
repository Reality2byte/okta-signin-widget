#!/bin/bash

# NOTE: MUST BE RAN *AFTER* THE PUBLISH SUITE

export PUBLISH_REGISTRY="${ARTIFACTORY_URL}/api/npm/npm-okta-all"
export PUBLIC_REGISTRY="https://registry.yarnpkg.com"

cd ${OKTA_HOME}/${REPO}

# Install required node version
setup_service node v16.19.1
setup_service yarn 1.22.19

# Install required dependencies
yarn global add @okta/ci-append-sha
yarn global add @okta/ci-pkginfo

export PATH="${PATH}:$(yarn global bin)"
export TEST_SUITE_TYPE="build"

# Append a SHA to the version in package.json
if ! ci-append-sha; then
  echo "ci-append-sha failed! Exiting..."
  exit $FAILED_SETUP
fi

# NOTE: hyphen rather than '@'
artifact_version="$(ci-pkginfo -t pkgname)-$(ci-pkginfo -t pkgsemver)"
published_tarball=${PUBLISH_REGISTRY}/@okta/okta-signin-widget/-/${artifact_version}.tgz

# clone angular sample, using angular sample because angular toolchain is *very* opinionated about modules
git clone --depth 1 https://github.com/okta/samples-js-angular.git test/package/angular-sample
pushd test/package/angular-sample/custom-login

# Get preconfigured .npmrc from /root, which contains the registry paths and necessary environment variables
cp /root/.npmrc .npmrc

# Override registry configs to point to the public registry since this repository is public
npm config set registry ${PUBLIC_REGISTRY}
npm config set @okta:registry ${PUBLIC_REGISTRY}

# use npm instead of yarn to test as a community dev
if ! npm i; then
  echo "install failed! Exiting..."
  exit ${FAILED_SETUP}
fi

# Point to the internal publish registry so we can get the unpromoted version from this topic branch's publish
npm config set @okta:registry ${PUBLISH_REGISTRY}

# install the version of @okta/okta-signin-widget from artifactory that was published during the `publish` suite
if ! npm i ${published_tarball}; then
  echo "npm install ${published_tarball} failed! Exiting..."
  exit ${FAILED_SETUP}
fi

# install the specific version of auth-js the widget depends on within the sample to prevent potential type errors
auth_js_version=$(cat node_modules/@okta/okta-signin-widget/package.json | jq -r ".dependencies[\"@okta/okta-auth-js\"]")
if ! npm i @okta/okta-auth-js@${auth_js_version}; then
  echo "install @okta/okta-auth-js@${auth_js_version} failed! Exiting..."
  exit ${FAILED_SETUP}
fi

export ISSUER="https://oie-signin-widget.okta.com"
export CLIENT_ID="0oa8lrg7ojTsbJgRQ696"

# Run build to verify siw installation
if ! npm run build; then
  echo "build failed! Exiting..."
  exit ${TEST_FAILURE}
fi

popd
exit $SUCCESS
