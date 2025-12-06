# User Accounts & Subscriptions: Clerk + RevenueCat Integration

This document outlines the integration plan for adding user accounts (Clerk) and subscription billing (RevenueCat) to rial.

## Overview

### Current State
- **Auth model**: Device-based (DCAppAttest + Ed25519 Secure Enclave keys)
- **User accounts**: None
- **Billing**: None

### Target State
- **Auth model**: Device attestation + optional user accounts
- **User accounts**: Clerk (social login, profiles, friends)
- **Billing**: RevenueCat (App Store subscriptions)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                           iOS App                                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────────┐  │
│  │   Clerk     │  │ RevenueCat  │  │  Existing Device Auth       │  │
│  │   SDK       │  │    SDK      │  │  (Attestation + Ed25519)    │  │
│  └──────┬──────┘  └──────┬──────┘  └──────────────┬──────────────┘  │
└─────────┼────────────────┼────────────────────────┼─────────────────┘
          │                │                        │
          ▼                ▼                        ▼
   ┌──────────────┐ ┌──────────────┐        ┌──────────────┐
   │    Clerk     │ │  RevenueCat  │        │  Rust API    │
   │   Backend    │ │   Backend    │        │  (Fly.io)    │
   └──────┬───────┘ └──────┬───────┘        └──────┬───────┘
          │                │                        │
          │    Webhooks    │    Webhooks           │
          └───────────┬────┴────────────┬──────────┘
                      ▼                 ▼
              ┌─────────────────────────────────┐
              │         Neon Postgres           │
              │  ┌───────────┐ ┌─────────────┐  │
              │  │  users    │ │ devices     │  │
              │  │  (Clerk)  │ │ (existing)  │  │
              │  └─────┬─────┘ └──────┬──────┘  │
              │        │              │         │
              │        └──────┬───────┘         │
              │               ▼                 │
              │  ┌─────────────────────────┐    │
              │  │    user_devices         │    │
              │  │ (links users↔devices)   │    │
              │  └─────────────────────────┘    │
              │  ┌─────────────────────────┐    │
              │  │    subscriptions        │    │
              │  │ (RevenueCat sync)       │    │
              │  └─────────────────────────┘    │
              │  ┌─────────────────────────┐    │
              │  │    friendships          │    │
              │  │ (social graph)          │    │
              │  └─────────────────────────┘    │
              └─────────────────────────────────┘
```

---

## Identity Model

### Key Insight: Devices ≠ Users

rial. has a unique challenge: **devices are already authenticated entities**. A user might:
- Use one device (common)
- Use multiple devices (upgrade phone, iPad + iPhone)
- Share a device (family iPad — edge case)

### Proposed Model

```
User (Clerk)
├── clerk_user_id (primary)
├── email
├── name
├── avatar_url
├── created_at
│
├── Devices (many)
│   ├── device_id (existing)
│   ├── linked_at
│   └── is_primary
│
├── Subscription (RevenueCat)
│   ├── rc_customer_id
│   ├── entitlement (free | pro | unlimited)
│   ├── expires_at
│   └── store (app_store | stripe)
│
└── Friends (many-to-many)
    └── friend_user_id
```

### Linking Flow

```
1. User installs app → device registered (existing flow)
2. User taps "Create Account" → Clerk sign-in (Apple/Google/Email)
3. App sends: POST /api/v1/users/link-device
   Body: { clerk_token, device_id, device_signature }
4. Backend verifies both, creates user_devices link
5. Future requests can include clerk_token OR device_signature (or both)
```

---

## Clerk Integration

### iOS SDK Setup

```swift
// Package.swift or SPM
.package(url: "https://github.com/clerk/clerk-ios", from: "1.0.0")
```

```swift
// AppDelegate.swift
import ClerkSDK

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Clerk.shared.configure(publishableKey: "pk_live_xxx")
        return true
    }
}
```

### Sign-In Options

| Method | Recommended | Notes |
|--------|-------------|-------|
| Sign in with Apple | ✅ Yes | Required for App Store if other social logins |
| Sign in with Google | ✅ Yes | Popular choice |
| Email + Password | Optional | More friction |
| Phone + OTP | Optional | Good for some markets |

### Backend Webhook Events

Clerk sends webhooks for user lifecycle events. Handle these in Rust:

```
POST /api/v1/webhooks/clerk

Events to handle:
- user.created     → Insert into users table
- user.updated     → Update users table
- user.deleted     → Soft delete, unlink devices
- session.created  → Optional: track logins
```

### JWT Verification (Rust)

```rust
// Cargo.toml
jsonwebtoken = "9"

// Verify Clerk JWT
use jsonwebtoken::{decode, DecodingKey, Validation, Algorithm};

pub async fn verify_clerk_token(token: &str) -> Result<ClerkClaims, AuthError> {
    // Fetch JWKS from Clerk (cache this)
    let jwks = fetch_clerk_jwks().await?;

    let decoded = decode::<ClerkClaims>(
        token,
        &DecodingKey::from_jwk(&jwks.keys[0])?,
        &Validation::new(Algorithm::RS256),
    )?;

    Ok(decoded.claims)
}
```

---

## RevenueCat Integration

### iOS SDK Setup

```swift
// Package.swift or SPM
.package(url: "https://github.com/RevenueCat/purchases-ios", from: "5.0.0")
```

```swift
// AppDelegate.swift
import RevenueCat

func application(_ application: UIApplication,
                 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

    Purchases.logLevel = .debug // Remove in production
    Purchases.configure(withAPIKey: "appl_xxx")

    // Link to Clerk user when signed in
    if let clerkUserId = Clerk.shared.user?.id {
        Purchases.shared.logIn(clerkUserId) { customerInfo, created, error in
            // User identified in RevenueCat
        }
    }

    return true
}
```

### Subscription Tiers

| Tier | Price | Limits | Features |
|------|-------|--------|----------|
| **Free** | $0 | 10 captures/month | Basic verification |
| **Pro** | $4.99/mo | 100 captures/month | Priority verification, history |
| **Unlimited** | $9.99/mo | Unlimited | All features, API access |

### Entitlements

RevenueCat uses "entitlements" to gate features:

```swift
// Check entitlement
Purchases.shared.getCustomerInfo { customerInfo, error in
    if customerInfo?.entitlements["pro"]?.isActive == true {
        // User has pro access
    }
}
```

### Backend Webhook Events

```
POST /api/v1/webhooks/revenuecat

Events to handle:
- INITIAL_PURCHASE      → Create/update subscription
- RENEWAL               → Extend subscription
- CANCELLATION          → Mark pending cancellation
- EXPIRATION            → Downgrade to free
- BILLING_ISSUE         → Alert user, grace period
- PRODUCT_CHANGE        → Upgrade/downgrade
```

### Webhook Payload (Example)

```json
{
  "api_version": "1.0",
  "event": {
    "type": "INITIAL_PURCHASE",
    "app_user_id": "clerk_user_xxx",
    "product_id": "rial_pro_monthly",
    "entitlement_ids": ["pro"],
    "purchased_at_ms": 1699000000000,
    "expiration_at_ms": 1701678000000,
    "store": "APP_STORE"
  }
}
```

---

## Database Schema Changes

### New Tables

```sql
-- Users (synced from Clerk)
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    clerk_user_id TEXT UNIQUE NOT NULL,
    email TEXT,
    name TEXT,
    avatar_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ  -- soft delete
);

-- Link users to devices (many-to-many)
CREATE TABLE user_devices (
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    device_id UUID REFERENCES devices(id) ON DELETE CASCADE,
    linked_at TIMESTAMPTZ DEFAULT NOW(),
    is_primary BOOLEAN DEFAULT FALSE,
    PRIMARY KEY (user_id, device_id)
);

-- Subscriptions (synced from RevenueCat)
CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    rc_customer_id TEXT NOT NULL,
    entitlement TEXT NOT NULL,  -- 'free', 'pro', 'unlimited'
    product_id TEXT,
    store TEXT,  -- 'app_store', 'play_store', 'stripe'
    purchased_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Friendships (social graph)
CREATE TABLE friendships (
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    friend_id UUID REFERENCES users(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'pending',  -- 'pending', 'accepted', 'blocked'
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, friend_id)
);

-- Indexes
CREATE INDEX idx_users_clerk_id ON users(clerk_user_id);
CREATE INDEX idx_subscriptions_user ON subscriptions(user_id);
CREATE INDEX idx_subscriptions_active ON subscriptions(user_id) WHERE is_active = TRUE;
CREATE INDEX idx_friendships_friend ON friendships(friend_id);
```

### Modify Existing Tables

```sql
-- Add optional user_id to captures (for social sharing)
ALTER TABLE captures ADD COLUMN user_id UUID REFERENCES users(id);
CREATE INDEX idx_captures_user ON captures(user_id);
```

---

## API Endpoints

### New Routes

```
Authentication:
POST   /api/v1/auth/link-device      # Link Clerk user to device
DELETE /api/v1/auth/unlink-device    # Unlink device from user

Users:
GET    /api/v1/users/me              # Get current user profile
PATCH  /api/v1/users/me              # Update profile
DELETE /api/v1/users/me              # Delete account (GDPR)

Friends:
GET    /api/v1/friends               # List friends
POST   /api/v1/friends/:user_id      # Send friend request
PATCH  /api/v1/friends/:user_id      # Accept/reject request
DELETE /api/v1/friends/:user_id      # Remove friend

Subscriptions:
GET    /api/v1/subscriptions/status  # Get current subscription
GET    /api/v1/subscriptions/usage   # Get usage stats

Sharing:
POST   /api/v1/captures/:id/share    # Share capture with friends
GET    /api/v1/shared                # Captures shared with me

Webhooks:
POST   /api/v1/webhooks/clerk        # Clerk events
POST   /api/v1/webhooks/revenuecat   # RevenueCat events
```

---

## Security Considerations

### Authentication Layers

| Endpoint Type | Auth Required |
|---------------|---------------|
| Device registration | Device attestation only |
| Capture upload | Device signature |
| User profile | Clerk JWT |
| Social features | Clerk JWT |
| Billing webhooks | Webhook signature verification |

### Webhook Security

```rust
// Clerk webhook verification
fn verify_clerk_webhook(payload: &[u8], signature: &str, secret: &str) -> bool {
    // Clerk uses Svix for webhooks
    let wh = svix::webhooks::Webhook::new(secret).unwrap();
    wh.verify(payload, &headers).is_ok()
}

// RevenueCat webhook verification
fn verify_revenuecat_webhook(auth_header: &str, expected: &str) -> bool {
    // RevenueCat uses Bearer token
    auth_header == format!("Bearer {}", expected)
}
```

### Data Privacy

- **PII storage**: Clerk handles sensitive PII (email, name)
- **Our DB**: Only stores clerk_user_id, not raw PII
- **GDPR**: Implement `/users/me` DELETE for right to erasure
- **Data export**: Implement data export endpoint

---

## Rate Limits & Quotas

### By Subscription Tier

| Resource | Free | Pro | Unlimited |
|----------|------|-----|-----------|
| Captures/month | 10 | 100 | ∞ |
| Video captures/month | 0 | 10 | ∞ |
| Max friends | 10 | 100 | 500 |
| API requests/day | 100 | 1,000 | 10,000 |
| Storage (captures) | 30 days | 1 year | Forever |

### Enforcement

```rust
pub async fn check_capture_quota(user_id: Uuid, pool: &PgPool) -> Result<(), QuotaError> {
    let subscription = get_active_subscription(user_id, pool).await?;
    let usage = get_monthly_capture_count(user_id, pool).await?;

    let limit = match subscription.entitlement.as_str() {
        "free" => 10,
        "pro" => 100,
        "unlimited" => i64::MAX,
        _ => 10,
    };

    if usage >= limit {
        return Err(QuotaError::LimitReached { usage, limit });
    }

    Ok(())
}
```

---

## Migration Path

### Phase 1: Backend Infrastructure
1. Add Clerk JWT verification middleware
2. Add webhook endpoints (Clerk + RevenueCat)
3. Create new database tables
4. Deploy to staging

### Phase 2: iOS Integration
1. Add Clerk SDK, implement sign-in UI
2. Add RevenueCat SDK, implement paywall
3. Implement device linking flow
4. Test on TestFlight

### Phase 3: Social Features
1. Implement friends list UI
2. Implement sharing flow
3. Implement shared captures view

### Phase 4: Web Dashboard
1. Add Clerk to Next.js app
2. User profile page
3. Subscription management
4. Friends/sharing on web

---

## Cost Estimates

### Monthly Costs (at scale)

| Service | Free Tier | At 10k MAU | At 100k MAU |
|---------|-----------|------------|-------------|
| **Clerk** | 10k MAU | $0 | ~$250/mo |
| **RevenueCat** | $2.5k MTR | $0* | ~$500/mo** |
| **Neon** | 0.5GB | ~$19/mo | ~$69/mo |
| **Fly.io** | 3 shared VMs | ~$20/mo | ~$100/mo |
| **Total** | - | ~$39/mo | ~$919/mo |

*Free until $2.5k monthly tracked revenue
**1% of MTR above $2.5k

### Break-Even Analysis

At $4.99/mo Pro tier with 5% conversion:
- 10k MAU → 500 subscribers → $2,495 MRR → Profitable
- 100k MAU → 5,000 subscribers → $24,950 MRR → Very profitable

---

## Environment Variables

### Backend (Fly.io secrets)

```bash
# Clerk
CLERK_SECRET_KEY=sk_live_xxx
CLERK_WEBHOOK_SECRET=whsec_xxx
CLERK_JWKS_URL=https://xxx.clerk.accounts.dev/.well-known/jwks.json

# RevenueCat
REVENUECAT_API_KEY=sk_xxx
REVENUECAT_WEBHOOK_AUTH=xxx
```

### iOS (Secrets in Xcode)

```
CLERK_PUBLISHABLE_KEY=pk_live_xxx
REVENUECAT_API_KEY=appl_xxx
```

### Web (Vercel env vars)

```bash
NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY=pk_live_xxx
CLERK_SECRET_KEY=sk_live_xxx
```

---

## Testing Strategy

### Unit Tests
- JWT verification logic
- Webhook signature verification
- Quota calculation

### Integration Tests
- Clerk webhook → user created in DB
- RevenueCat webhook → subscription updated
- Device linking flow

### E2E Tests
- Full sign-up → link device → subscribe flow
- Friend request → accept → share capture flow

---

## Open Questions

1. **Anonymous captures**: Should captures made before sign-up be linkable to accounts?
2. **Device transfer**: What happens when user gets new phone?
3. **Family sharing**: Support App Store family sharing?
4. **Web subscriptions**: Stripe for web-only users (avoid App Store cut)?
5. **Friend discovery**: Allow finding friends by contacts/email?

---

## References

- [Clerk iOS SDK Docs](https://clerk.com/docs/quickstarts/ios)
- [RevenueCat iOS Docs](https://www.revenuecat.com/docs/ios-native-quick-start)
- [Clerk Webhooks](https://clerk.com/docs/integrations/webhooks)
- [RevenueCat Webhooks](https://www.revenuecat.com/docs/webhooks)
- [App Store Review Guidelines - In-App Purchase](https://developer.apple.com/app-store/review/guidelines/#in-app-purchase)
