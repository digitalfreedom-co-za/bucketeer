#!/usr/bin/env python3
"""Create the four wiki-standard Xcode Cloud workflows for Bucketeer.

Prerequisite (one-time, manual): Xcode Cloud must be onboarded for the
Bucketeer product — Xcode > Integrate > Create Workflow… > select
"Bucketeer". That wizard creates the ciProduct and links the GitHub
repository; the App Store Connect API cannot do either (both resources
reject CREATE — verified 2026-07-05). Delete the placeholder workflow
the wizard creates afterwards or keep it; this script only adds the
missing wiki workflows and never edits existing ones.

Wiki reference (~/Developer/projects/wiki/apple-native-apps.md):
  01. Development Build — development branch, quality gate
  02. Testflight Build  — test branch, Archive -> TestFlight internal
  03. Beta Release      — beta branch, Archive -> TestFlight external
  04. Release Build     — main branch, Archive -> App Store

Note: workflow 01 runs Analyze (which builds) instead of the wiki's
Test+Analyze because the Xcode project has no test target yet; the
BucketeerCore SPM tests run in GitHub Actions. Switch the action to
TEST once a test target exists.

TestFlight group assignment (Internal/External) is not part of the
workflow API — assign groups once in App Store Connect > TestFlight
after the first archive of each workflow.

Environment (defaults match the aso repo layout):
  ASC_KEY_ID     App Store Connect API key id
  ASC_ISSUER_ID  issuer id
  ASC_KEY_PATH   path to the AuthKey .p8
"""

import json
import os
import sys
import time
import urllib.request

try:
    import jwt
except ImportError:
    sys.exit("PyJWT missing: pip3 install PyJWT cryptography")

KEY_ID = os.environ.get("ASC_KEY_ID", "59YFSG364Q")
ISSUER = os.environ.get("ASC_ISSUER_ID", "1c4d3c69-dd83-4276-96d0-97b7b773da92")
KEY_PATH = os.environ.get(
    "ASC_KEY_PATH",
    os.path.expanduser("~/Developer/aso/keys/AuthKey_59YFSG364Q.p8"),
)

PRODUCT_NAME = "Bucketeer"
REPO_NAME = "bucketeer"
SCHEME = "Bucketeer"


def token() -> str:
    with open(KEY_PATH) as f:
        pk = f.read()
    return jwt.encode(
        {"iss": ISSUER, "iat": int(time.time()) - 30,
         "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
        pk, algorithm="ES256", headers={"kid": KEY_ID},
    )


def call(method: str, path: str, body=None):
    req = urllib.request.Request(
        "https://api.appstoreconnect.apple.com" + path, method=method,
        headers={"Authorization": f"Bearer {token()}",
                 "Content-Type": "application/json"},
        data=json.dumps(body).encode() if body else None,
    )
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, (json.load(r) if r.status != 204 else {})
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def find(data, predicate):
    return next((d for d in data if predicate(d)), None)


def main() -> None:
    s, r = call("GET", "/v1/ciProducts?filter[productType]=APP&limit=50")
    assert s == 200, r
    product = find(r["data"], lambda p: p["attributes"]["name"] == PRODUCT_NAME)
    if product is None:
        sys.exit(
            f"ciProduct '{PRODUCT_NAME}' not found — run the one-time "
            "Xcode onboarding first (Xcode > Integrate > Create Workflow…)."
        )
    product_id = product["id"]
    print("ciProduct:", product_id)

    s, r = call("GET", "/v1/scmRepositories?limit=50")
    assert s == 200, r
    repo = find(r["data"],
                lambda x: x["attributes"]["repositoryName"] == REPO_NAME)
    if repo is None:
        sys.exit("scmRepository 'bucketeer' not linked — the Xcode "
                 "onboarding wizard links it.")
    repo_id = repo["id"]
    print("repository:", repo_id)

    s, r = call("GET", "/v1/ciXcodeVersions?limit=50")
    xcode = find(r["data"], lambda x: x["attributes"]["name"] == "Latest Release")
    assert xcode, "no 'Latest Release' Xcode version"
    s, r = call("GET", "/v1/ciMacOsVersions?limit=50")
    macos = find(r["data"], lambda x: x["attributes"]["name"] == "Latest Release")
    assert macos, "no 'Latest Release' macOS version"
    print("xcode:", xcode["id"], "| macos:", macos["id"])

    s, r = call("GET", f"/v1/ciProducts/{product_id}/workflows?limit=50")
    existing = {w["attributes"]["name"] for w in r.get("data", [])}
    print("existing workflows:", existing or "none")

    def action(kind: str, audience: str | None = None) -> dict:
        base = {
            "name": {"ANALYZE": "Analyze", "ARCHIVE": "Archive"}[kind],
            "actionType": kind,
            "scheme": SCHEME,
            "platform": "MACOS",
            "isRequiredToPass": True,
        }
        if audience:
            base["buildDistributionAudience"] = audience
        return base

    def branch_condition(branch: str) -> dict:
        return {
            "source": {"isAllMatch": False,
                       "patterns": [{"pattern": branch, "isPrefix": False}]},
            "autoCancel": True,
        }

    workflows = [
        ("01. Development Build",
         "Quality gate on the development branch (wiki 01). Analyze "
         "builds the app; SPM tests run in GitHub Actions until a test "
         "target exists.",
         "development", [action("ANALYZE")]),
        ("02. Testflight Build",
         "test branch -> Archive -> TestFlight internal testing (wiki 02).",
         "test", [action("ARCHIVE", "INTERNAL_ONLY")]),
        ("03. Beta Release",
         "beta branch -> Archive -> TestFlight external testing (wiki 03).",
         "beta", [action("ARCHIVE", "APP_STORE_ELIGIBLE")]),
        ("04. Release Build",
         "main branch -> Archive -> App Store submission (wiki 04).",
         "main", [action("ARCHIVE", "APP_STORE_ELIGIBLE")]),
    ]

    for name, description, branch, actions in workflows:
        if name in existing:
            print(f"skip (exists): {name}")
            continue
        s, r = call("POST", "/v1/ciWorkflows", {
            "data": {
                "type": "ciWorkflows",
                "attributes": {
                    "name": name,
                    "description": description,
                    "branchStartCondition": branch_condition(branch),
                    "actions": actions,
                    "isEnabled": True,
                    "isLockedForEditing": False,
                    "clean": False,
                    "containerFilePath": "Bucketeer.xcodeproj",
                },
                "relationships": {
                    "product": {"data": {"type": "ciProducts", "id": product_id}},
                    "repository": {"data": {"type": "scmRepositories", "id": repo_id}},
                    "xcodeVersion": {"data": {"type": "ciXcodeVersions", "id": xcode["id"]}},
                    "macOsVersion": {"data": {"type": "ciMacOsVersions", "id": macos["id"]}},
                },
            }
        })
        print(f"create {name}: {s}",
              r["data"]["id"] if s in (200, 201) else r)


if __name__ == "__main__":
    main()
