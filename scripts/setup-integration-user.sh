#!/usr/bin/env bash
set -euo pipefail

ORG="${1:-funcircle}"
INT_USER="${2:-communityos.mcp@funcircle.ca}"
NOTIFY_EMAIL="${3:-admin@funcircle.ca}"

PROFILE_ID=$(sf data query --target-org "$ORG" --json \
  --query "SELECT Id FROM Profile WHERE Name = 'Minimum Access - API Only Integrations'" \
  | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>console.log(JSON.parse(s).result.records[0].Id))")

EXISTS=$(sf data query --target-org "$ORG" --json \
  --query "SELECT COUNT() FROM User WHERE Username = '$INT_USER'" \
  | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>console.log(JSON.parse(s).result.totalSize))")

if [ "$EXISTS" = "0" ]; then
  sf data create record --target-org "$ORG" --sobject User --values \
    "Username=$INT_USER LastName=MCP FirstName=CommunityOS Alias=cosmcp Email=$NOTIFY_EMAIL ProfileId=$PROFILE_ID TimeZoneSidKey=America/Vancouver LocaleSidKey=en_CA EmailEncodingKey=UTF-8 LanguageLocaleKey=en_US"
fi

sf org assign permsetlicense --name SalesforceAPIIntegrationPsl --on-behalf-of "$INT_USER" --target-org "$ORG" || true
sf org assign permset --name CommunityOS_Graph_Read --on-behalf-of "$INT_USER" --target-org "$ORG"

sf data query --target-org "$ORG" \
  --query "SELECT PermissionSet.Name FROM PermissionSetAssignment WHERE Assignee.Username = '$INT_USER' AND PermissionSet.IsOwnedByProfile = false"
