//! Challenge store service for DCAppAttest verification
//!
//! Provides in-memory storage for attestation challenges with:
//! - 5-minute TTL (time-to-live) for challenges
//! - Single-use challenges (invalidated after verification)
//! - Rate limiting per IP address (10 challenges/minute)
//! - Background cleanup of expired challenges

use chrono::{DateTime, Duration, Utc};
use rand::{rngs::OsRng, RngCore};
use std::collections::HashMap;
use std::net::IpAddr;
use std::sync::Arc;
use tokio::sync::RwLock;

/// Challenge entry stored in the challenge store
#[derive(Debug, Clone)]
pub struct ChallengeEntry {
    /// The 32-byte challenge value
    pub challenge: [u8; 32],
    /// When this challenge expires
    pub expires_at: DateTime<Utc>,
    /// Whether this challenge has been used
    pub used: bool,
}

/// Rate limit entry tracking requests per IP
#[derive(Debug, Clone)]
struct RateLimitEntry {
    /// Number of requests in the current window
    count: u32,
    /// When the current window started
    window_start: DateTime<Utc>,
}

/// Thread-safe in-memory challenge store with rate limiting
#[derive(Debug)]
pub struct ChallengeStore {
    /// Challenges indexed by their value for O(1) lookup
    challenges: RwLock<HashMap<[u8; 32], ChallengeEntry>>,
    /// Rate limit tracking per IP address
    rate_limits: RwLock<HashMap<IpAddr, RateLimitEntry>>,
}

/// Challenge TTL in minutes
const CHALLENGE_TTL_MINUTES: i64 = 5;

/// Rate limit: max challenges per IP per minute
const RATE_LIMIT_MAX: u32 = 10;

/// Rate limit window in minutes
const RATE_LIMIT_WINDOW_MINUTES: i64 = 1;

/// Errors that can occur during challenge operations
#[derive(Debug, Clone, PartialEq)]
pub enum ChallengeError {
    /// Challenge was not found in the store
    NotFound,
    /// Challenge has already been used
    AlreadyUsed,
    /// Challenge has expired
    Expired,
    /// Rate limit exceeded for this IP
    RateLimitExceeded,
}

impl std::fmt::Display for ChallengeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ChallengeError::NotFound => write!(f, "Challenge not found"),
            ChallengeError::AlreadyUsed => write!(f, "Challenge already used"),
            ChallengeError::Expired => write!(f, "Challenge expired"),
            ChallengeError::RateLimitExceeded => write!(f, "Rate limit exceeded"),
        }
    }
}

impl std::error::Error for ChallengeError {}

impl ChallengeStore {
    /// Creates a new challenge store wrapped in an Arc for shared ownership
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            challenges: RwLock::new(HashMap::new()),
            rate_limits: RwLock::new(HashMap::new()),
        })
    }

    /// Checks if the given IP address has exceeded the rate limit.
    /// Returns Ok(()) if within limit, Err(RateLimitExceeded) if exceeded.
    /// Increments the counter if within limit.
    pub async fn check_rate_limit(&self, ip: IpAddr) -> Result<(), ChallengeError> {
        let now = Utc::now();
        let mut limits = self.rate_limits.write().await;

        let entry = limits.entry(ip).or_insert(RateLimitEntry {
            count: 0,
            window_start: now,
        });

        // Reset window if more than 1 minute has passed
        if now - entry.window_start > Duration::minutes(RATE_LIMIT_WINDOW_MINUTES) {
            entry.count = 0;
            entry.window_start = now;
        }

        if entry.count >= RATE_LIMIT_MAX {
            return Err(ChallengeError::RateLimitExceeded);
        }

        entry.count += 1;
        Ok(())
    }

    /// Generates a new cryptographically secure challenge.
    /// Returns the challenge bytes and expiration timestamp.
    pub async fn generate_challenge(&self) -> ([u8; 32], DateTime<Utc>) {
        let mut challenge = [0u8; 32];
        OsRng.fill_bytes(&mut challenge);

        let expires_at = Utc::now() + Duration::minutes(CHALLENGE_TTL_MINUTES);

        let entry = ChallengeEntry {
            challenge,
            expires_at,
            used: false,
        };

        self.challenges.write().await.insert(challenge, entry);

        (challenge, expires_at)
    }

    /// Verifies a challenge and marks it as used.
    /// Returns Ok(()) if the challenge is valid, unexpired, and unused.
    pub async fn verify_and_consume(&self, challenge: &[u8; 32]) -> Result<(), ChallengeError> {
        let mut challenges = self.challenges.write().await;

        let entry = challenges
            .get_mut(challenge)
            .ok_or(ChallengeError::NotFound)?;

        if entry.used {
            return Err(ChallengeError::AlreadyUsed);
        }

        if Utc::now() > entry.expires_at {
            return Err(ChallengeError::Expired);
        }

        entry.used = true;
        Ok(())
    }

    /// Removes all expired challenges from the store.
    /// Should be called periodically via a background task.
    pub async fn cleanup_expired(&self) {
        let now = Utc::now();
        let mut challenges = self.challenges.write().await;
        let before_count = challenges.len();
        challenges.retain(|_, entry| entry.expires_at > now);
        let removed = before_count - challenges.len();
        if removed > 0 {
            tracing::debug!(removed = removed, "Cleaned up expired challenges");
        }

        // Also cleanup old rate limit entries (older than 5 minutes)
        let mut rate_limits = self.rate_limits.write().await;
        rate_limits.retain(|_, entry| now - entry.window_start < Duration::minutes(5));
    }

    /// Spawns a background task that periodically cleans up expired challenges.
    /// Returns a handle that can be used to abort the task.
    pub fn spawn_cleanup_task(store: Arc<Self>) -> tokio::task::JoinHandle<()> {
        tokio::spawn(async move {
            let mut interval = tokio::time::interval(tokio::time::Duration::from_secs(60));
            loop {
                interval.tick().await;
                store.cleanup_expired().await;
            }
        })
    }
}

impl Default for ChallengeStore {
    fn default() -> Self {
        Self {
            challenges: RwLock::new(HashMap::new()),
            rate_limits: RwLock::new(HashMap::new()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::Ipv4Addr;

    #[tokio::test]
    async fn test_generate_challenge_returns_32_bytes() {
        let store = ChallengeStore::new();
        let (challenge, _expires_at) = store.generate_challenge().await;
        assert_eq!(challenge.len(), 32);
    }

    #[tokio::test]
    async fn test_challenge_expires_in_5_minutes() {
        let store = ChallengeStore::new();
        let (_, expires_at) = store.generate_challenge().await;
        let now = Utc::now();
        let diff = expires_at - now;
        // Allow 1 second tolerance for test execution time
        assert!(diff.num_minutes() >= 4 && diff.num_minutes() <= 5);
    }

    #[tokio::test]
    async fn test_verify_and_consume_success() {
        let store = ChallengeStore::new();
        let (challenge, _) = store.generate_challenge().await;
        let result = store.verify_and_consume(&challenge).await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_challenge_single_use() {
        let store = ChallengeStore::new();
        let (challenge, _) = store.generate_challenge().await;

        // First use should succeed
        let result1 = store.verify_and_consume(&challenge).await;
        assert!(result1.is_ok());

        // Second use should fail
        let result2 = store.verify_and_consume(&challenge).await;
        assert_eq!(result2, Err(ChallengeError::AlreadyUsed));
    }

    #[tokio::test]
    async fn test_unknown_challenge_not_found() {
        let store = ChallengeStore::new();
        let unknown_challenge = [0u8; 32];
        let result = store.verify_and_consume(&unknown_challenge).await;
        assert_eq!(result, Err(ChallengeError::NotFound));
    }

    #[tokio::test]
    async fn test_rate_limiting() {
        let store = ChallengeStore::new();
        let ip: IpAddr = Ipv4Addr::new(192, 168, 1, 1).into();

        // First 10 requests should succeed
        for _ in 0..10 {
            assert!(store.check_rate_limit(ip).await.is_ok());
        }

        // 11th request should be rate limited
        let result = store.check_rate_limit(ip).await;
        assert_eq!(result, Err(ChallengeError::RateLimitExceeded));
    }

    #[tokio::test]
    async fn test_rate_limit_different_ips() {
        let store = ChallengeStore::new();
        let ip1: IpAddr = Ipv4Addr::new(192, 168, 1, 1).into();
        let ip2: IpAddr = Ipv4Addr::new(192, 168, 1, 2).into();

        // Exhaust limit for ip1
        for _ in 0..10 {
            assert!(store.check_rate_limit(ip1).await.is_ok());
        }

        // ip2 should still be allowed
        assert!(store.check_rate_limit(ip2).await.is_ok());

        // ip1 should be blocked
        assert_eq!(
            store.check_rate_limit(ip1).await,
            Err(ChallengeError::RateLimitExceeded)
        );
    }

    #[tokio::test]
    async fn test_cleanup_removes_expired() {
        let store = ChallengeStore::new();

        // Generate a challenge
        let (challenge, _) = store.generate_challenge().await;

        // Manually set it as expired
        {
            let mut challenges = store.challenges.write().await;
            if let Some(entry) = challenges.get_mut(&challenge) {
                entry.expires_at = Utc::now() - Duration::minutes(1);
            }
        }

        // Cleanup should remove it
        store.cleanup_expired().await;

        // Should no longer be found
        let result = store.verify_and_consume(&challenge).await;
        assert_eq!(result, Err(ChallengeError::NotFound));
    }
}
