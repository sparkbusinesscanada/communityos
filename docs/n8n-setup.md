# n8n: daily owner brief

**What it does:** every morning at 7:00 (Vancouver time), n8n reads a read-only summary from Salesforce and emails it to the owner only. It never writes to Salesforce and never contacts customers.

**Flow:** Schedule (7:00) → HTTP GET `https://funcircle.my.salesforce.com/services/apexrest/communityos/brief` (Salesforce OAuth2) → Code node formats the email → Gmail sends it.

The workflow file is `n8n/owner-daily-brief.json`. The endpoint is the Apex class `OwnerBriefApi` (read-only, no contact details).

## One-time setup (owner)
1. **Create a Salesforce app for n8n.** In production: Setup → App Manager → **New External Client App** (or New Connected App).
   - Enable OAuth.
   - Callback URL: copy the **OAuth Redirect URL** shown on n8n's Salesforce credential screen (step 2).
   - Scopes: *Manage user data via APIs (api)* and *Perform requests at any time (refresh_token, offline_access)*.
   - Save, then copy the **Consumer Key** and **Consumer Secret**.
2. **Add the Salesforce credential in n8n.** Production enforces PKCE, so use the generic credential: Credentials → New → **OAuth2 API**.
   - Grant Type: **PKCE**
   - Authorization URL: `https://login.salesforce.com/services/oauth2/authorize`
   - Access Token URL: `https://login.salesforce.com/services/oauth2/token`
   - Client ID / Secret: Consumer Key / Secret
   - Scope: `api refresh_token offline_access`
   - Authentication: **Send credentials in body**
   - Click **Connect** and sign in as yourself.
3. **Add the Gmail credential in n8n.** Credentials → New → **Gmail OAuth2** → Sign in with Google.
4. **Import the workflow.** Workflows → Import from file → `n8n/owner-daily-brief.json`.
5. **Set credentials on two nodes.**
   - On "Get brief from Salesforce", pick the OAuth2 API credential.
   - On "Email the owner", pick the Gmail credential and replace `OWNER_EMAIL_HERE` with your address.
6. Click **Test workflow**, check the email, then switch the workflow **Active**.
