import crypto from "node:crypto";
import fs from "node:fs/promises";

const {
    ASC_KEY_ID,
    ASC_ISSUER_ID,
    ASC_PRIVATE_KEY,
    ASC_BUNDLE_ID,
    ASC_BETA_GROUP_NAME
} = process.env;

function required(name, value) {
    if (!value) {
        throw new Error(`Missing environment variable: ${name}`);
    }
}

required("ASC_KEY_ID", ASC_KEY_ID);
required("ASC_ISSUER_ID", ASC_ISSUER_ID);
required("ASC_PRIVATE_KEY", ASC_PRIVATE_KEY);
required("ASC_BUNDLE_ID", ASC_BUNDLE_ID);
required("ASC_BETA_GROUP_NAME", ASC_BETA_GROUP_NAME);

const privateKey = ASC_PRIVATE_KEY.replace(/\\n/g, "\n");

function base64URL(value) {
    return Buffer
        .from(JSON.stringify(value))
        .toString("base64url");
}

function createJWT() {
    const now = Math.floor(Date.now() / 1000);

    const header = {
        alg: "ES256",
        kid: ASC_KEY_ID,
        typ: "JWT"
    };

    const payload = {
        iss: ASC_ISSUER_ID,
        iat: now - 30,
        exp: now + 10 * 60,
        aud: "appstoreconnect-v1"
    };

    const encodedHeader = base64URL(header);
    const encodedPayload = base64URL(payload);

    const signingInput = `${encodedHeader}.${encodedPayload}`;

    const signature = crypto.sign(
        "sha256",
        Buffer.from(signingInput),
        {
            key: privateKey,
            dsaEncoding: "ieee-p1363"
        }
    );

    return `${signingInput}.${signature.toString("base64url")}`;
}

const token = createJWT();

async function apiRequest(pathOrURL) {
    const url = pathOrURL.startsWith("http")
        ? pathOrURL
        : `https://api.appstoreconnect.apple.com${pathOrURL}`;

    const response = await fetch(url, {
        headers: {
            Authorization: `Bearer ${token}`,
            Accept: "application/json"
        }
    });

    if (!response.ok) {
        const body = await response.text();

        throw new Error(
            `App Store Connect API ${response.status}: ${body}`
        );
    }

    return response.json();
}

async function pagedRequest(path) {
    let url = path;
    const result = [];

    while (url) {
        const json = await apiRequest(url);

        if (Array.isArray(json.data)) {
            result.push(...json.data);
        }

        url = json.links?.next ?? null;
    }

    return result;
}

// MARK: - Find App

const appsQuery = new URLSearchParams({
    "filter[bundleId]": ASC_BUNDLE_ID,
    "fields[apps]": "name,bundleId"
});

const apps = await apiRequest(
    `/v1/apps?${appsQuery.toString()}`
);

if (!apps.data?.length) {
    throw new Error(
        `App not found for bundle id: ${ASC_BUNDLE_ID}`
    );
}

const app = apps.data[0];

console.log(
    `Found app: ${app.attributes.name} (${app.attributes.bundleId})`
);

// MARK: - Find Beta Group

const groupQuery = new URLSearchParams({
    limit: "200",
    "fields[betaGroups]":
        "name,isInternalGroup,hasAccessToAllBuilds,publicLinkEnabled,publicLink"
});

const groups = await apiRequest(
    `/v1/apps/${app.id}/betaGroups?${groupQuery.toString()}`
);

const group = groups.data?.find(
    item => item.attributes?.name === ASC_BETA_GROUP_NAME
);

if (!group) {
    const names = (groups.data ?? [])
        .map(item => item.attributes?.name)
        .join(", ");

    throw new Error(
        `Beta group "${ASC_BETA_GROUP_NAME}" not found. Existing groups: ${names}`
    );
}

console.log(
    `Found Beta Group: ${group.attributes.name}`
);

// MARK: - Read Builds

const buildsQuery = new URLSearchParams({
    limit: "200",
    "fields[builds]":
        "version,uploadedDate,expirationDate,expired,processingState,buildAudienceType"
});

let builds = await pagedRequest(
    `/v1/betaGroups/${group.id}/builds?${buildsQuery.toString()}`
);

builds = builds
    .filter(item => {
        const attr = item.attributes;

        return attr &&
            attr.expired !== true &&
            attr.processingState === "VALID";
    })
    .sort((a, b) => {
        return new Date(b.attributes.uploadedDate)
            - new Date(a.attributes.uploadedDate);
    });

if (!builds.length) {
    throw new Error(
        "No VALID, non-expired builds found in beta group."
    );
}

// MARK: - Find a build that is actually testing

let latestBuild = null;
let betaState = null;

for (const build of builds) {

    const detail = await apiRequest(
        `/v1/builds/${build.id}/buildBetaDetail?fields%5BbuildBetaDetails%5D=internalBuildState,externalBuildState`
    );

    const attributes = detail.data?.attributes;

    if (!attributes) {
        continue;
    }

    const state = group.attributes.isInternalGroup
        ? attributes.internalBuildState
        : attributes.externalBuildState;

    console.log(
        `Build ${build.attributes.version}: ${state}`
    );

    if (state === "IN_BETA_TESTING") {
        latestBuild = build;
        betaState = state;
        break;
    }
}

if (!latestBuild) {
    throw new Error(
        "No build currently in IN_BETA_TESTING state."
    );
}

console.log(
    `Selected build: ${latestBuild.attributes.version}`
);

// MARK: - Read marketing version

const buildInfoQuery = new URLSearchParams({
    include: "preReleaseVersion",
    "fields[builds]":
        "version,uploadedDate,expirationDate,expired,processingState",
    "fields[preReleaseVersions]":
        "version,platform"
});

const buildInfo = await apiRequest(
    `/v1/builds/${latestBuild.id}?${buildInfoQuery.toString()}`
);

const preReleaseVersion = buildInfo.included?.find(
    item => item.type === "preReleaseVersions"
);

if (!preReleaseVersion) {
    throw new Error(
        "Unable to resolve CFBundleShortVersionString."
    );
}

const marketingVersion =
    preReleaseVersion.attributes.version;

const buildNumber =
    buildInfo.data.attributes.version;

// MARK: - Read TestFlight What's New

const localizationQuery = new URLSearchParams({
    limit: "200",
    "fields[betaBuildLocalizations]":
        "locale,whatsNew"
});

const localizations = await apiRequest(
    `/v1/builds/${latestBuild.id}/betaBuildLocalizations?${localizationQuery.toString()}`
);

const releaseNotes = {};

for (const item of localizations.data ?? []) {
    const locale = item.attributes?.locale;
    const whatsNew = item.attributes?.whatsNew;

    if (locale && whatsNew) {
        releaseNotes[locale] = whatsNew;
    }
}

// MARK: - Load policy

const policyRaw = await fs.readFile(
    "Config/TestFlight/policy.json",
    "utf8"
);

const policy = JSON.parse(policyRaw);

// MARK: - Build Manifest

const manifest = {
    schemaVersion: 1,

    generatedAt: new Date().toISOString(),

    app: {
        name: app.attributes.name,
        bundleId: app.attributes.bundleId
    },

    betaGroup: {
        name: group.attributes.name,
        isInternal: group.attributes.isInternalGroup,
        state: betaState
    },

    latest: {
        version: marketingVersion,
        build: buildNumber,
        buildId: latestBuild.id,
        uploadedAt:
            buildInfo.data.attributes.uploadedDate,
        expiresAt:
            buildInfo.data.attributes.expirationDate
    },

    testFlight: {
        url: group.attributes.publicLink ?? null
    },

    releaseNotes,

    policy
};

// MARK: - Generate GitHub Pages

await fs.mkdir(
    ".pages/testflight",
    {
        recursive: true
    }
);

await fs.writeFile(
    ".pages/testflight/version.json",
    JSON.stringify(
        manifest,
        null,
        2
    )
);

await fs.writeFile(
    ".pages/.nojekyll",
    ""
);

await fs.writeFile(
    ".pages/index.html",
    `
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>CrazyDashboard TestFlight</title>
</head>
<body>
<h1>CrazyDashboard TestFlight Version Service</h1>
<p><a href="./testflight/version.json">version.json</a></p>
</body>
</html>
`
);

console.log("");
console.log("Generated manifest:");
console.log(
    JSON.stringify(
        manifest,
        null,
        2
    )
);