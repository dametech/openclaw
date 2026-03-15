# OpenClaw Integrations Research - March 2026

This document summarizes research findings for OpenClaw integrations with enterprise systems. Based on this research, 23 implementation tasks have been created.

## 1. Per-Agent API Key Automation

### Key Findings

**External Secrets Management (v2026.2.26+)**
- New `openclaw secrets` workflow with four commands: `audit`, `configure`, `apply`, `reload`
- Runtime snapshot activation - manage API keys without restarting gateway
- Secret reference authentication (SecretRefs) instead of embedded keys
- Supports: 1Password CLI, HashiCorp Vault, env vars, files, exec commands

**Per-Agent Configuration**
- Agents can have separate workspaces and authentication profiles
- Provider rotation on rate limits
- Per-provider API key configuration: `openclaw models auth paste-token --provider anthropic`
- Multiple agents can run in single Gateway process with isolated credentials

### Resources
- [Multi-Agent Routing - OpenClaw](https://docs.openclaw.ai/concepts/multi-agent)
- [OpenClaw v2026.2.26 Release](https://openclawlaunch.com/news/openclaw-v2026-2-26-external-secrets-acp-agents)
- [Multi-Agent Setup Guide](https://lumadock.com/tutorials/openclaw-multi-agent-setup)

---

## 2. Microsoft 365 SharePoint Integration

### Key Findings

**Authentication Methods**
- **Azure AD OAuth 2.0**: App registration in Azure Portal required
- **Federated Identity Credentials (FIC)**: Via Agentic Blueprint for agent identity
- **On-Behalf-Of (OBO) Flow**: Agent operates with user's permissions, not global admin
- **Service Principal**: For headless access patterns

**Available Skills**
- `openclaw-a365` - Microsoft 365 Agents channel with Graph API tools (alpha)
- `ms365` - Microsoft 365 integration skill
- `office365-connector` - OAuth with automatic token refresh

**Security & Compliance**
- All access appears in Microsoft 365 audit logs
- Documents inherit permissions from library/site hierarchy
- Agent respects enterprise permission controls
- Per-account secure token isolation

**Important Note**
- Microsoft Graph CLI (msgraph-cli) archived August 2025, retired 2026
- Must use modern Microsoft Graph API integration

### Resources
- [SharePoint & OneDrive Integration](https://www.getopenclaw.ai/en/integrations/sharepoint)
- [GitHub: openclaw-a365](https://github.com/SidU/openclaw-a365)
- [Microsoft 365 Integration Skill](https://openclaw.army/skills/cvsloane/ms365/)

---

## 3. Slack Integration

### Key Findings

**Deployment Options (2026)**
- **Socket Mode** (Default): Long-lived WebSocket, no public URL required
- **HTTP Events API Mode**: Alternative webhook-based approach
- Multi-workspace deployment support for agencies/holding companies
- Estimated setup time: 25-40 minutes

**Required Tokens**
- App Token (xapp-...)
- Bot Token (xoxb-...)
- WebSocket connection maintained by OpenClaw

**Features**
- DMs and channel support (production-ready)
- Slash commands for quick actions
- Scheduled messages via cron integration
- User approval/pairing: `openclaw pairing approve slack <code>`
- Allowlist/blocklist security controls

**Security**
- Blocks unapproved users by default
- No inbound HTTP endpoint needed (Socket Mode)
- Safe for testing behind firewalls

### Resources
- [Official Slack Integration Docs](https://docs.openclaw.ai/channels/slack)
- [Complete Integration Guide](https://www.c-sharpcorner.com/article/the-complete-guide-to-integrating-slack-with-openclaw-2026-the-steps-most-ai/)
- [Secure Setup Guide](https://lumadock.com/tutorials/openclaw-slack-integration)

---

## 4. Microsoft Teams Integration

### Key Findings

**Architecture Changes (January 2026)**
- Teams integration moved **out of core package** - now a separate plugin
- Keeps main install light, allows independent updates
- Integration via Azure Bot Framework (webhook-based)

**Message Flow**
```
User in Teams → Bot Framework Service → webhook POST to Gateway (port 3978)
→ OpenClaw processes → reply via Bot Framework API → Teams delivers response
```

**Setup Requirements**
- Azure Bot (App ID + client secret + tenant ID)
- Expose `/api/messages` endpoint (port 3978) via public URL or tunnel
- Teams App Manifest (manifest.json)
- Bot icons: outline.png (32×32), color.png (192×192)

**CRITICAL DEPRECATION**
- **Multi-tenant bot creation deprecated after 2025-07-31**
- **Use Single Tenant for all new bots**

**Communication Policies**
- Channels and group chats: disabled (default), allowlist, or open
- Requires @mention in channels and group chats by default
- Private channel support rolling out in 2026 (not all tenants yet)

### Resources
- [Official Teams Integration Docs](https://docs.openclaw.ai/channels/msteams)
- [Enterprise Integration Guide](https://clawdbotmoltbot.com/openclaw-microsoft-teams-integration)
- [Setup Guide](https://open-claw.bot/docs/channels/msteams/)

---

## 5. 1Password Integration

### Key Findings

**Core Functionality**
- Integrates with 1Password CLI (`op`) for runtime secret injection
- No hardcoded credentials, no environment variable sprawl
- Secrets resolved into in-memory runtime snapshot
- Resolution is eager during activation (not lazy on request)

**v2026.2.26 Features**
- Complete `openclaw secrets` workflow
- Four new commands: `audit`, `configure`, `apply`, `reload`
- Runtime snapshot activation without gateway restart
- `openclaw secrets audit --check` identifies plaintext credentials

**Secret Reference Format**
```
op://vault/item/field
```

**Security Model**
- Secrets live in 1Password vault
- Service account token is only thing on disk
- Access logs available in 1Password for audit trail
- Supports multiple secret providers: 1Password CLI, HashiCorp Vault, env, files, exec

**Implementation Pattern**
- Store service account token securely
- Reference secrets in openclaw.json using `op://` URIs
- OpenClaw fetches and injects as environment variables at runtime
- Never expose credentials in configuration files

**Known Issues**
- GitHub issue #29183: launchd env propagation on macOS
- SecretRefs validation in string-only fields

### Resources
- [Official Secrets Management Docs](https://docs.openclaw.ai/gateway/secrets)
- [Securing OpenClaw with 1Password](https://prokopov.me/posts/securing-openclaw-with-1password/)
- [1Password Skill Documentation](https://github.com/openclaw/openclaw/blob/main/skills/1password/SKILL.md)

---

## 6. Jira Integration

### Key Findings

**Backend Options**
- **Jira CLI**: Atlassian command-line tool
- **Atlassian MCP**: Model Context Protocol integration
- **Direct REST API**: With managed OAuth
- **Expanso Pipelines**: Pipeline-based integration

**Available Skills**
- `jira` - Core Jira integration skill
- `jira-api` - REST API focused integration
- `jira-ai` - AI-enhanced Jira automation

**Capabilities**
- Create, view, update, delete issues programmatically
- Manage sprints and track progress
- Run JQL queries for filtering and reporting
- Automate workflow transitions and status changes
- Bulk updates and scripting
- CI/CD pipeline integration
- Generate reproducible metrics for sprint reviews

**Security Model**
- API token stored in environment variable (local machine)
- Neither OpenClaw nor AI models see Jira credentials
- All API calls go directly from machine to Atlassian servers
- Tokens referenced via 1Password integration

**Use Cases**
- Automate issue workflows in CI/CD pipelines
- Script bulk updates and JQL reports
- Embed Jira operations in automation agents
- Natural language ticket creation and updates

### Resources
- [Jira Integration Guide](https://expanso.io/expanso-hearts-openclaw/jira/)
- [Official Jira Integration](https://www.getopenclaw.ai/integrations/jira)
- [GitHub Integration Guide](https://apidog.com/blog/openclaw-development-workflow/)

---

## Implementation Task Breakdown

Based on this research, 23 tasks have been created covering:

### Phase 1: Foundation (Tasks 1-3)
- Research per-agent API key automation
- Design multi-agent Kubernetes architecture
- Implement automated API key provisioning

### Phase 2: Microsoft 365 SharePoint (Tasks 4-6)
- Research authentication methods
- Set up Azure AD app registration
- Implement and test SharePoint skill

### Phase 3: Slack Integration (Tasks 7-9)
- Research deployment options
- Create Slack app and configure tokens
- Deploy and test channel integration

### Phase 4: Microsoft Teams (Tasks 10-13)
- Research integration architecture
- Set up Azure Bot and manifest
- Expose webhook endpoint in Kubernetes
- Deploy with named bot identities

### Phase 5: 1Password Automation (Tasks 14-16)
- Research integration patterns
- Set up service accounts and vaults
- Implement secret injection in Kubernetes

### Phase 6: Jira Integration (Tasks 17-19)
- Research integration options
- Set up API token and connectivity
- Deploy and test integration skill

### Phase 7: Integration & Testing (Tasks 20-23)
- Create unified deployment script
- Test multi-agent communication
- Document security model
- Create monitoring and alerting

---

## Key Considerations

### Security
- Use 1Password or HashiCorp Vault for all credentials
- Never commit plaintext credentials to git
- Use `openclaw secrets audit --check` regularly
- Enable audit logging in all integrations (M365, Jira, etc.)

### Multi-Agent Architecture
- Decide: separate pods per agent or single pod with multiple agents
- Consider PVC strategy (shared vs isolated workspaces)
- Plan for inter-agent communication patterns
- Design naming conventions for agent identities

### Kubernetes Deployment
- Use Helm charts for templating multi-agent deployments
- Implement proper secret management (Kubernetes secrets + 1Password)
- Plan for webhook exposure (Teams requires public endpoint)
- Configure network policies for security

### Monitoring & Observability
- Track authentication failures across all integrations
- Monitor webhook delivery (Teams)
- Monitor Socket Mode connectivity (Slack)
- Alert on rate limits and quota exhaustion

### Compliance & Audit
- Ensure all actions appear in audit logs (M365, Jira)
- Document access patterns for compliance reviews
- Implement least-privilege access for all service accounts
- Plan for credential rotation procedures

---

## Next Steps

1. Review and prioritize the 23 tasks based on business needs
2. Assign owners for each integration area
3. Set up development/testing environment
4. Begin with Phase 1 (Foundation) to establish multi-agent architecture
5. Implement integrations incrementally with testing at each phase
6. Document learnings and update procedures as needed

---

**Last Updated**: March 16, 2026
**Research Version**: Based on OpenClaw v2026.2.26+ and March 2026 documentation
