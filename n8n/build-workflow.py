"""Builds the two n8n workflows (daily brief, weekly AI review) from the Code node sources in n8n/src.

Run: python3 n8n/build-workflow.py
"""
import json
import pathlib

HERE = pathlib.Path(__file__).parent
SF = "https://funcircle.my.salesforce.com"


def code(name):
    return (HERE / "src" / name).read_text()


def trigger(cron, name):
    return {"parameters": {"rule": {"interval": [{"field": "cronExpression", "expression": cron}]}},
            "name": name, "type": "n8n-nodes-base.scheduleTrigger", "typeVersion": 1.2, "position": [0, 0]}


def sf_get(path, name):
    return {"parameters": {"url": SF + path, "authentication": "genericCredentialType", "genericAuthType": "oAuth2Api", "options": {}},
            "name": name, "type": "n8n-nodes-base.httpRequest", "typeVersion": 4.2, "position": [220, 0]}


def code_node(src, name, x, y=0, notes=None):
    n = {"parameters": {"jsCode": code(src)}, "name": name, "type": "n8n-nodes-base.code", "typeVersion": 2, "position": [x, y]}
    if notes:
        n["notes"] = notes
    return n


def gmail(x):
    return {"parameters": {"sendTo": "OWNER_EMAIL_HERE", "subject": "={{ $json.subject }}", "emailType": "html",
                           "message": "={{ $json.html }}", "options": {"appendAttribution": False}},
            "name": "Email the owner", "type": "n8n-nodes-base.gmail", "typeVersion": 2.1, "position": [x, 0]}


def link(*targets):
    return {"main": [[{"node": t, "type": "main", "index": 0} for t in targets]]}


def save(filename, name, nodes, connections):
    wf = {"name": name, "nodes": nodes, "connections": connections,
          "settings": {"timezone": "America/Vancouver", "executionOrder": "v1"}, "pinData": {}}
    (HERE / filename).write_text(json.dumps(wf, indent=2) + "\n")
    print("wrote", filename, len(nodes), "nodes")


# Daily: exact numbers and fixed rules, no AI
save("owner-daily-brief.json", "CommunityOS - Daily owner brief", [
    trigger("0 7 * * *", "Every day 7:00"),
    sf_get("/services/apexrest/communityos/brief", "Get brief from Salesforce"),
    code_node("rules-and-facts.js", "Rules and facts", 440, notes="Deterministic: numbered facts and fixed rules. No AI."),
    code_node("build-email.js", "Build email", 660),
    gmail(880),
], {
    "Every day 7:00": link("Get brief from Salesforce"),
    "Get brief from Salesforce": link("Rules and facts"),
    "Rules and facts": link("Build email"),
    "Build email": link("Email the owner"),
})

# Weekly: deterministic facts and rules, then Claude's review, checked, logged and emailed
save("owner-weekly-review.json", "CommunityOS - Weekly business review (AI)", [
    trigger("0 7 * * 1", "Every Monday 7:00"),
    sf_get("/services/apexrest/communityos/weekly", "Get weekly data from Salesforce"),
    code_node("weekly-rules-and-facts.js", "Weekly rules and facts", 440,
              notes="Deterministic: funnel, conversion, pace, seasonality, booking changes and fixed rules. No AI."),
    {
        "parameters": {
            "conditions": {
                "options": {"caseSensitive": True, "leftValue": "", "typeValidation": "strict"},
                "conditions": [{"id": "ai-budget-left", "leftValue": "={{ $json.aiAllowed }}", "rightValue": "",
                                "operator": {"type": "boolean", "operation": "true", "singleValue": True}}],
                "combinator": "and",
            },
            "options": {},
        },
        "name": "AI budget left?", "type": "n8n-nodes-base.if", "typeVersion": 2, "position": [660, 0],
    },
    {
        "parameters": {
            "method": "POST", "url": "https://api.anthropic.com/v1/messages",
            "authentication": "genericCredentialType", "genericAuthType": "httpHeaderAuth",
            "sendHeaders": True,
            "headerParameters": {"parameters": [{"name": "anthropic-version", "value": "2023-06-01"}]},
            "sendBody": True, "specifyBody": "json", "jsonBody": "={{ JSON.stringify($json.claudeRequest) }}",
            "options": {"timeout": 120000},
        },
        "name": "Ask Claude", "type": "n8n-nodes-base.httpRequest", "typeVersion": 4.2, "position": [880, -120],
        "onError": "continueRegularOutput", "retryOnFail": True, "maxTries": 2, "waitBetweenTries": 5000,
        "notes": "Claude sees only counts, rates and rule results: no names, no contact details, no children.",
    },
    code_node("check-claude-answer.js", "Check Claude's answer", 1100, -120,
              notes="Deterministic guardrail: valid JSON, known fact IDs, no numbers outside the facts, max 4 actions."),
    {
        "parameters": {
            "method": "POST", "url": SF + "/services/data/v62.0/sobjects/AI_Call_Log__c",
            "authentication": "genericCredentialType", "genericAuthType": "oAuth2Api",
            "sendBody": True, "specifyBody": "json", "jsonBody": "={{ JSON.stringify($json.logRecord) }}", "options": {},
        },
        "name": "Log the call in Salesforce", "type": "n8n-nodes-base.httpRequest", "typeVersion": 4.2, "position": [1320, -240],
        "onError": "continueRegularOutput",
    },
    code_node("weekly-email.js", "Build weekly email", 1320),
    gmail(1540),
], {
    "Every Monday 7:00": link("Get weekly data from Salesforce"),
    "Get weekly data from Salesforce": link("Weekly rules and facts"),
    "Weekly rules and facts": link("AI budget left?"),
    "AI budget left?": {"main": [[{"node": "Ask Claude", "type": "main", "index": 0}],
                                 [{"node": "Build weekly email", "type": "main", "index": 0}]]},
    "Ask Claude": link("Check Claude's answer"),
    "Check Claude's answer": link("Log the call in Salesforce", "Build weekly email"),
    "Build weekly email": link("Email the owner"),
})
