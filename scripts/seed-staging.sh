#!/usr/bin/env bash
# Barazo Staging Seed Script
#
# Populates the staging database with test data for development and QA.
# Run after reset-staging.sh or on a fresh staging deployment.
#
# Usage:
#   ./scripts/seed-staging.sh                # Seed all test data
#   ./scripts/seed-staging.sh --minimal      # Seed only categories (faster)
#
# What it creates:
#   - 5 top-level categories + 7 subcategories (12 total)
#   - 5 test users (admin, moderator, 3 members) with known DIDs
#   - 10 sample topics across categories
#   - 18 flat replies across topics
#   - 15-level deep reply thread (Raspberry Pi self-hosting topic)
#   - 1 forum-wide pinned topic + 1 category-pinned topic + 1 locked topic
#   - Moderation data: queue items, action log, word filter
#
# Prerequisites:
#   - Staging services must be running
#   - Database must have migrations applied (API does this on startup)
#   - COMMUNITY_DID must be set in .env
#
# Environment:
#   COMPOSE_CMD    Docker Compose command override
#   COMMUNITY_DID  AT Protocol community DID (required, loaded from .env)

set -euo pipefail

COMPOSE_CMD="${COMPOSE_CMD:-docker compose -f docker-compose.yml -f docker-compose.staging.yml}"
MINIMAL=false

# Parse arguments
for arg in "$@"; do
  case "$arg" in
    --minimal) MINIMAL=true ;;
    --help|-h)
      echo "Usage: $0 [--minimal]"
      echo ""
      echo "Seeds the staging database with test data."
      echo ""
      echo "Options:"
      echo "  --minimal    Only create categories (skip users, topics, replies)"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

# Load .env for database credentials and COMMUNITY_DID
if [ -f .env ]; then
  # shellcheck disable=SC2046
  export $(grep -v '^#' .env | grep -v '^\s*$' | xargs)
fi

DB_NAME="${POSTGRES_DB:-barazo_staging}"
DB_USER="${POSTGRES_USER:-barazo}"

if [ -z "${COMMUNITY_DID:-}" ]; then
  echo "Error: COMMUNITY_DID is not set. Add it to .env or export it." >&2
  exit 1
fi

echo "Using COMMUNITY_DID: $COMMUNITY_DID"

# Verify PostgreSQL is running
if ! $COMPOSE_CMD exec -T postgres pg_isready -U "$DB_USER" &>/dev/null; then
  echo "Error: PostgreSQL is not running. Start services first:" >&2
  echo "  docker compose -f docker-compose.yml -f docker-compose.staging.yml up -d" >&2
  exit 1
fi

# Helper: run psql with COMMUNITY_DID available as a psql variable
run_psql() {
  $COMPOSE_CMD exec -T postgres psql -U "$DB_USER" -d "$DB_NAME" \
    -v community_did="'$COMMUNITY_DID'"
}

echo "Seeding staging database..."
echo ""

# --- Categories (with subcategories) ---
echo "Creating categories..."
run_psql <<'SQL'
-- Top-level categories
INSERT INTO categories (id, slug, name, description, parent_id, sort_order, community_did, maturity_rating, created_at, updated_at)
VALUES
  ('cat-general',     'general',     'General',      'General discussion about anything',               NULL, 1, :community_did, 'safe', NOW(), NOW()),
  ('cat-feedback',    'feedback',    'Feedback',     'Feature requests, bug reports, and suggestions',   NULL, 2, :community_did, 'safe', NOW(), NOW()),
  ('cat-development', 'development', 'Development',  'Technical discussions about building with Barazo', NULL, 3, :community_did, 'safe', NOW(), NOW()),
  ('cat-atproto',     'atproto',     'AT Protocol',  'AT Protocol ecosystem, standards, and tooling',    NULL, 4, :community_did, 'safe', NOW(), NOW()),
  ('cat-off-topic',   'off-topic',   'Off-Topic',    'Casual conversations and community hangout',       NULL, 5, :community_did, 'safe', NOW(), NOW())
ON CONFLICT DO NOTHING;

-- Subcategories under Development
INSERT INTO categories (id, slug, name, description, parent_id, sort_order, community_did, maturity_rating, created_at, updated_at)
VALUES
  ('cat-dev-frontend', 'frontend', 'Frontend',  'UI, components, and client-side development',  'cat-development', 1, :community_did, 'safe', NOW(), NOW()),
  ('cat-dev-backend',  'backend',  'Backend',   'API, database, and server-side development',   'cat-development', 2, :community_did, 'safe', NOW(), NOW()),
  ('cat-dev-infra',    'infra',    'Infrastructure', 'Deployment, Docker, CI/CD, and hosting', 'cat-development', 3, :community_did, 'safe', NOW(), NOW())
ON CONFLICT DO NOTHING;

-- Subcategories under Feedback
INSERT INTO categories (id, slug, name, description, parent_id, sort_order, community_did, maturity_rating, created_at, updated_at)
VALUES
  ('cat-fb-features', 'feature-requests', 'Feature Requests', 'Suggest new features and improvements',  'cat-feedback', 1, :community_did, 'safe', NOW(), NOW()),
  ('cat-fb-bugs',     'bug-reports',      'Bug Reports',      'Report bugs and unexpected behavior',     'cat-feedback', 2, :community_did, 'safe', NOW(), NOW())
ON CONFLICT DO NOTHING;

-- Subcategories under AT Protocol
INSERT INTO categories (id, slug, name, description, parent_id, sort_order, community_did, maturity_rating, created_at, updated_at)
VALUES
  ('cat-atp-lexicons', 'lexicons',  'Lexicons',  'Schema definitions and data model discussions',     'cat-atproto', 1, :community_did, 'safe', NOW(), NOW()),
  ('cat-atp-identity', 'identity',  'Identity',  'DIDs, handles, and portable identity',              'cat-atproto', 2, :community_did, 'safe', NOW(), NOW())
ON CONFLICT DO NOTHING;
SQL
echo "  Categories and subcategories created."

if [ "$MINIMAL" = true ]; then
  echo ""
  echo "Minimal seed complete (categories only)."
  exit 0
fi

# --- Test Users ---
# Users table has no community_did (global across communities)
echo "Creating test users..."
run_psql <<'SQL'
INSERT INTO users (did, handle, display_name, role, first_seen_at, last_active_at)
VALUES
  ('did:plc:staging-admin-001',     'staging-admin.bsky.social',     'Staging Admin',     'admin',     NOW(), NOW()),
  ('did:plc:staging-moderator-001', 'staging-mod.bsky.social',       'Staging Moderator', 'moderator', NOW(), NOW()),
  ('did:plc:staging-member-001',    'staging-member.bsky.social',    'Staging Member',    'user',      NOW(), NOW()),
  ('did:plc:staging-member-002',    'staging-member2.bsky.social',   'Test User Two',     'user',      NOW(), NOW()),
  ('did:plc:staging-member-003',    'staging-member3.bsky.social',   'Test User Three',   'user',      NOW(), NOW())
ON CONFLICT (did) DO NOTHING;
SQL
echo "  Test users created."

# --- Topics ---
# AT Protocol style: uri is the primary key, references author by DID, category by slug
echo "Creating sample topics..."
run_psql <<'SQL'
INSERT INTO topics (uri, rkey, author_did, title, content, category, community_did, cid, reply_count, created_at, last_activity_at, is_pinned, pinned_at, pinned_scope, is_locked)
VALUES
  -- Forum-wide pinned announcement
  ('at://did:plc:staging-admin-001/forum.barazo.topic.post/3seed001',
   '3seed001', 'did:plc:staging-admin-001',
   'Welcome to Barazo Staging',
   'This is the staging instance of Barazo, used for testing and development. Feel free to create topics and test features.',
   'general', :community_did, 'bafyseed-t01', 3,
   NOW() - INTERVAL '7 days', NOW() - INTERVAL '6 days 18 hours',
   true, NOW() - INTERVAL '7 days', 'forum', false),

  -- Category-pinned in feedback + locked
  ('at://did:plc:staging-admin-001/forum.barazo.topic.post/3seed002',
   '3seed002', 'did:plc:staging-admin-001',
   'How to report bugs',
   'Found a bug? Describe what you expected to happen, what actually happened, and steps to reproduce.',
   'feedback', :community_did, 'bafyseed-t02', 3,
   NOW() - INTERVAL '6 days', NOW() - INTERVAL '5 days 18 hours',
   true, NOW() - INTERVAL '6 days', 'category', true),

  ('at://did:plc:staging-moderator-001/forum.barazo.topic.post/3seed003',
   '3seed003', 'did:plc:staging-moderator-001',
   'Getting started with the Barazo API',
   'The Barazo API is a RESTful API built with Fastify. You can explore the API documentation at /docs.',
   'development', :community_did, 'bafyseed-t03', 3,
   NOW() - INTERVAL '5 days', NOW() - INTERVAL '4 days 14 hours',
   false, NULL, NULL, false),

  ('at://did:plc:staging-moderator-001/forum.barazo.topic.post/3seed004',
   '3seed004', 'did:plc:staging-moderator-001',
   'AT Protocol identity and portability',
   'One of the key features of building on AT Protocol is portable identity. Your DID stays with you across communities.',
   'atproto', :community_did, 'bafyseed-t04', 3,
   NOW() - INTERVAL '4 days', NOW() - INTERVAL '3 days 14 hours',
   false, NULL, NULL, false),

  ('at://did:plc:staging-member-001/forum.barazo.topic.post/3seed005',
   '3seed005', 'did:plc:staging-member-001',
   'Favorite open source projects?',
   'What open source projects are you excited about right now? Share your favorites!',
   'off-topic', :community_did, 'bafyseed-t05', 3,
   NOW() - INTERVAL '3 days', NOW() - INTERVAL '2 days 12 hours',
   false, NULL, NULL, false),

  ('at://did:plc:staging-member-001/forum.barazo.topic.post/3seed006',
   '3seed006', 'did:plc:staging-member-001',
   'Feature request: dark mode improvements',
   'The dark mode is great but could use some contrast improvements in the sidebar and category labels.',
   'feedback', :community_did, 'bafyseed-t06', 3,
   NOW() - INTERVAL '2 days', NOW() - INTERVAL '1 day 12 hours',
   false, NULL, NULL, false),

  ('at://did:plc:staging-admin-001/forum.barazo.topic.post/3seed007',
   '3seed007', 'did:plc:staging-admin-001',
   'Understanding the firehose and Tap',
   'Tap filters the AT Protocol firehose for forum.barazo.* records. Here is how it works and why it matters.',
   'development', :community_did, 'bafyseed-t07', 0,
   NOW() - INTERVAL '2 days', NOW() - INTERVAL '2 days',
   false, NULL, NULL, false),

  ('at://did:plc:staging-moderator-001/forum.barazo.topic.post/3seed008',
   '3seed008', 'did:plc:staging-moderator-001',
   'Cross-community reputation design',
   'How should reputation work across multiple Barazo communities? Let us discuss the design considerations.',
   'atproto', :community_did, 'bafyseed-t08', 0,
   NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day',
   false, NULL, NULL, false),

  ('at://did:plc:staging-member-001/forum.barazo.topic.post/3seed009',
   '3seed009', 'did:plc:staging-member-001',
   'Self-hosting Barazo on a Raspberry Pi',
   'Has anyone tried running Barazo on a Raspberry Pi? Curious about the performance on ARM hardware.',
   'general', :community_did, 'bafyseed-t09', 15,
   NOW() - INTERVAL '12 hours', NOW() - INTERVAL '1 hour',
   false, NULL, NULL, false),

  ('at://did:plc:staging-member-001/forum.barazo.topic.post/3seed010',
   '3seed010', 'did:plc:staging-member-001',
   'Weekend project ideas',
   'Looking for weekend project ideas that integrate with AT Protocol. What are you building?',
   'off-topic', :community_did, 'bafyseed-t10', 0,
   NOW() - INTERVAL '6 hours', NOW() - INTERVAL '6 hours',
   false, NULL, NULL, false)
ON CONFLICT DO NOTHING;
SQL
echo "  Sample topics created."

# --- Flat Replies (depth 1, across multiple topics) ---
echo "Creating sample replies..."
run_psql <<'SQL'
-- Welcome topic replies (flat, depth 1)
INSERT INTO replies (uri, rkey, author_did, content, root_uri, root_cid, parent_uri, parent_cid, community_did, cid, depth, created_at)
VALUES
  ('at://did:plc:staging-moderator-001/forum.barazo.reply.post/3seedr01',
   '3seedr01', 'did:plc:staging-moderator-001',
   'Great to see the staging environment up and running!',
   'at://did:plc:staging-admin-001/forum.barazo.topic.post/3seed001', 'bafyseed-t01',
   'at://did:plc:staging-admin-001/forum.barazo.topic.post/3seed001', 'bafyseed-t01',
   :community_did, 'bafyseed-r01', 1, NOW() - INTERVAL '6 days 23 hours'),

  ('at://did:plc:staging-member-001/forum.barazo.reply.post/3seedr02',
   '3seedr02', 'did:plc:staging-member-001',
   'Testing the reply functionality. Markdown **bold** and *italic* work well.',
   'at://did:plc:staging-admin-001/forum.barazo.topic.post/3seed001', 'bafyseed-t01',
   'at://did:plc:staging-admin-001/forum.barazo.topic.post/3seed001', 'bafyseed-t01',
   :community_did, 'bafyseed-r02', 1, NOW() - INTERVAL '6 days 20 hours'),

  ('at://did:plc:staging-member-002/forum.barazo.reply.post/3seedr03',
   '3seedr03', 'did:plc:staging-member-002',
   'Confirmed everything looks good on mobile too.',
   'at://did:plc:staging-admin-001/forum.barazo.topic.post/3seed001', 'bafyseed-t01',
   'at://did:plc:staging-admin-001/forum.barazo.topic.post/3seed001', 'bafyseed-t01',
   :community_did, 'bafyseed-r03', 1, NOW() - INTERVAL '6 days 18 hours'),

  -- Bug report topic replies
  ('at://did:plc:staging-moderator-001/forum.barazo.reply.post/3seedr04',
   '3seedr04', 'did:plc:staging-moderator-001',
   'I can help triage bugs as they come in.',
   'at://did:plc:staging-admin-001/forum.barazo.topic.post/3seed002', 'bafyseed-t02',
   'at://did:plc:staging-admin-001/forum.barazo.topic.post/3seed002', 'bafyseed-t02',
   :community_did, 'bafyseed-r04', 1, NOW() - INTERVAL '5 days 22 hours'),

  ('at://did:plc:staging-member-001/forum.barazo.reply.post/3seedr05',
   '3seedr05', 'did:plc:staging-member-001',
   'Is there a template for bug reports?',
   'at://did:plc:staging-admin-001/forum.barazo.topic.post/3seed002', 'bafyseed-t02',
   'at://did:plc:staging-admin-001/forum.barazo.topic.post/3seed002', 'bafyseed-t02',
   :community_did, 'bafyseed-r05', 1, NOW() - INTERVAL '5 days 20 hours'),

  ('at://did:plc:staging-admin-001/forum.barazo.reply.post/3seedr06',
   '3seedr06', 'did:plc:staging-admin-001',
   'Not yet, but that is a good idea. Will add one.',
   'at://did:plc:staging-admin-001/forum.barazo.topic.post/3seed002', 'bafyseed-t02',
   'at://did:plc:staging-admin-001/forum.barazo.topic.post/3seed002', 'bafyseed-t02',
   :community_did, 'bafyseed-r06', 1, NOW() - INTERVAL '5 days 18 hours'),

  -- API topic replies
  ('at://did:plc:staging-member-001/forum.barazo.reply.post/3seedr07',
   '3seedr07', 'did:plc:staging-member-001',
   'The Fastify integration is really clean. Love the Zod validation.',
   'at://did:plc:staging-moderator-001/forum.barazo.topic.post/3seed003', 'bafyseed-t03',
   'at://did:plc:staging-moderator-001/forum.barazo.topic.post/3seed003', 'bafyseed-t03',
   :community_did, 'bafyseed-r07', 1, NOW() - INTERVAL '4 days 20 hours'),

  ('at://did:plc:staging-member-002/forum.barazo.reply.post/3seedr08',
   '3seedr08', 'did:plc:staging-member-002',
   'How does rate limiting work on the API?',
   'at://did:plc:staging-moderator-001/forum.barazo.topic.post/3seed003', 'bafyseed-t03',
   'at://did:plc:staging-moderator-001/forum.barazo.topic.post/3seed003', 'bafyseed-t03',
   :community_did, 'bafyseed-r08', 1, NOW() - INTERVAL '4 days 16 hours'),

  ('at://did:plc:staging-admin-001/forum.barazo.reply.post/3seedr09',
   '3seedr09', 'did:plc:staging-admin-001',
   'Rate limiting uses a sliding window stored in Valkey. Configurable per endpoint.',
   'at://did:plc:staging-moderator-001/forum.barazo.topic.post/3seed003', 'bafyseed-t03',
   'at://did:plc:staging-moderator-001/forum.barazo.topic.post/3seed003', 'bafyseed-t03',
   :community_did, 'bafyseed-r09', 1, NOW() - INTERVAL '4 days 14 hours'),

  -- Identity topic replies
  ('at://did:plc:staging-member-001/forum.barazo.reply.post/3seedr10',
   '3seedr10', 'did:plc:staging-member-001',
   'This is the killer feature of AT Protocol-based forums.',
   'at://did:plc:staging-moderator-001/forum.barazo.topic.post/3seed004', 'bafyseed-t04',
   'at://did:plc:staging-moderator-001/forum.barazo.topic.post/3seed004', 'bafyseed-t04',
   :community_did, 'bafyseed-r10', 1, NOW() - INTERVAL '3 days 20 hours'),

  ('at://did:plc:staging-member-003/forum.barazo.reply.post/3seedr11',
   '3seedr11', 'did:plc:staging-member-003',
   'Can I use my existing Bluesky handle to sign in?',
   'at://did:plc:staging-moderator-001/forum.barazo.topic.post/3seed004', 'bafyseed-t04',
   'at://did:plc:staging-moderator-001/forum.barazo.topic.post/3seed004', 'bafyseed-t04',
   :community_did, 'bafyseed-r11', 1, NOW() - INTERVAL '3 days 16 hours'),

  ('at://did:plc:staging-moderator-001/forum.barazo.reply.post/3seedr12',
   '3seedr12', 'did:plc:staging-moderator-001',
   'Yes! Any AT Protocol account works via OAuth. Bluesky, Blacksky, self-hosted PDS, all supported.',
   'at://did:plc:staging-moderator-001/forum.barazo.topic.post/3seed004', 'bafyseed-t04',
   'at://did:plc:staging-moderator-001/forum.barazo.topic.post/3seed004', 'bafyseed-t04',
   :community_did, 'bafyseed-r12', 1, NOW() - INTERVAL '3 days 14 hours'),

  -- OSS topic replies
  ('at://did:plc:staging-moderator-001/forum.barazo.reply.post/3seedr13',
   '3seedr13', 'did:plc:staging-moderator-001',
   'Valkey has been great as a Redis replacement.',
   'at://did:plc:staging-member-001/forum.barazo.topic.post/3seed005', 'bafyseed-t05',
   'at://did:plc:staging-member-001/forum.barazo.topic.post/3seed005', 'bafyseed-t05',
   :community_did, 'bafyseed-r13', 1, NOW() - INTERVAL '2 days 20 hours'),

  ('at://did:plc:staging-member-002/forum.barazo.reply.post/3seedr14',
   '3seedr14', 'did:plc:staging-member-002',
   'I have been enjoying Caddy for reverse proxy. So much simpler than nginx.',
   'at://did:plc:staging-member-001/forum.barazo.topic.post/3seed005', 'bafyseed-t05',
   'at://did:plc:staging-member-001/forum.barazo.topic.post/3seed005', 'bafyseed-t05',
   :community_did, 'bafyseed-r14', 1, NOW() - INTERVAL '2 days 16 hours'),

  ('at://did:plc:staging-admin-001/forum.barazo.reply.post/3seedr15',
   '3seedr15', 'did:plc:staging-admin-001',
   'Drizzle ORM is another good one. TypeScript-first database queries.',
   'at://did:plc:staging-member-001/forum.barazo.topic.post/3seed005', 'bafyseed-t05',
   'at://did:plc:staging-member-001/forum.barazo.topic.post/3seed005', 'bafyseed-t05',
   :community_did, 'bafyseed-r15', 1, NOW() - INTERVAL '2 days 12 hours'),

  -- Dark mode topic replies
  ('at://did:plc:staging-moderator-001/forum.barazo.reply.post/3seedr16',
   '3seedr16', 'did:plc:staging-moderator-001',
   'Agreed on the sidebar contrast. The category pills are hard to read in dark mode.',
   'at://did:plc:staging-member-001/forum.barazo.topic.post/3seed006', 'bafyseed-t06',
   'at://did:plc:staging-member-001/forum.barazo.topic.post/3seed006', 'bafyseed-t06',
   :community_did, 'bafyseed-r16', 1, NOW() - INTERVAL '1 day 20 hours'),

  ('at://did:plc:staging-admin-001/forum.barazo.reply.post/3seedr17',
   '3seedr17', 'did:plc:staging-admin-001',
   'We use Radix Colors which should handle this well. Will investigate.',
   'at://did:plc:staging-member-001/forum.barazo.topic.post/3seed006', 'bafyseed-t06',
   'at://did:plc:staging-member-001/forum.barazo.topic.post/3seed006', 'bafyseed-t06',
   :community_did, 'bafyseed-r17', 1, NOW() - INTERVAL '1 day 16 hours'),

  ('at://did:plc:staging-member-003/forum.barazo.reply.post/3seedr18',
   '3seedr18', 'did:plc:staging-member-003',
   'Maybe the Flexoki accent hues need adjustment for the dark palette.',
   'at://did:plc:staging-member-001/forum.barazo.topic.post/3seed006', 'bafyseed-t06',
   'at://did:plc:staging-member-001/forum.barazo.topic.post/3seed006', 'bafyseed-t06',
   :community_did, 'bafyseed-r18', 1, NOW() - INTERVAL '1 day 12 hours')
ON CONFLICT DO NOTHING;
SQL
echo "  Flat replies created."

# --- Deep Thread (15 levels) on the Raspberry Pi topic ---
# A single chain of replies where each is a child of the previous one.
# Cycles through all 5 test users for realistic variety.
echo "Creating deep reply thread (15 levels)..."
run_psql <<'SQL'
-- Raspberry Pi self-hosting topic: deep threaded conversation
-- Topic URI: at://did:plc:staging-member-001/forum.barazo.topic.post/3seed009
-- Each reply is a child of the previous, forming a single chain depth 1-15.

-- Users cycle: admin(001), mod(001), member(001), member(002), member(003), admin, mod, ...
INSERT INTO replies (uri, rkey, author_did, content, root_uri, root_cid, parent_uri, parent_cid, community_did, cid, depth, created_at)
VALUES
  -- Depth 1: member-002 replies to topic
  ('at://did:plc:staging-member-002/forum.barazo.reply.post/3seeddeep01',
   '3seeddeep01', 'did:plc:staging-member-002',
   'I actually have it running on a Pi 4 with 8GB RAM. Works surprisingly well.',
   'at://did:plc:staging-member-001/forum.barazo.topic.post/3seed009', 'bafyseed-t09',
   'at://did:plc:staging-member-001/forum.barazo.topic.post/3seed009', 'bafyseed-t09',
   :community_did, 'bafyseed-d01', 1, NOW() - INTERVAL '11 hours'),

  -- Depth 2: member-003 replies to depth 1
  ('at://did:plc:staging-member-003/forum.barazo.reply.post/3seeddeep02',
   '3seeddeep02', 'did:plc:staging-member-003',
   'What about the database? PostgreSQL on a Pi seems heavy.',
   'at://did:plc:staging-member-001/forum.barazo.topic.post/3seed009', 'bafyseed-t09',
   'at://did:plc:staging-member-002/forum.barazo.reply.post/3seeddeep01', 'bafyseed-d01',
   :community_did, 'bafyseed-d02', 2, NOW() - INTERVAL '10 hours'),

  -- Depth 3: admin replies to depth 2
  ('at://did:plc:staging-admin-001/forum.barazo.reply.post/3seeddeep03',
   '3seeddeep03', 'did:plc:staging-admin-001',
   'SQLite would be lighter but you lose concurrent writes. PostgreSQL is fine with proper tuning.',
   'at://did:plc:staging-member-001/forum.barazo.topic.post/3seed009', 'bafyseed-t09',
   'at://did:plc:staging-member-003/forum.barazo.reply.post/3seeddeep02', 'bafyseed-d02',
   :community_did, 'bafyseed-d03', 3, NOW() - INTERVAL '9 hours'),

  -- Depth 4: member-002 replies to depth 3
  ('at://did:plc:staging-member-002/forum.barazo.reply.post/3seeddeep04',
   '3seeddeep04', 'did:plc:staging-member-002',
   'What pg settings did you change? I keep running out of shared memory.',
   'at://did:plc:staging-member-001/forum.barazo.topic.post/3seed009', 'bafyseed-t09',
   'at://did:plc:staging-admin-001/forum.barazo.reply.post/3seeddeep03', 'bafyseed-d03',
   :community_did, 'bafyseed-d04', 4, NOW() - INTERVAL '8 hours 30 minutes'),

  -- Depth 5: mod replies to depth 4
  ('at://did:plc:staging-moderator-001/forum.barazo.reply.post/3seeddeep05',
   '3seeddeep05', 'did:plc:staging-moderator-001',
   'Set shared_buffers to 256MB and work_mem to 16MB. Also reduce max_connections to 20.',
   'at://did:plc:staging-member-001/forum.barazo.topic.post/3seed009', 'bafyseed-t09',
   'at://did:plc:staging-member-002/forum.barazo.reply.post/3seeddeep04', 'bafyseed-d04',
   :community_did, 'bafyseed-d05', 5, NOW() - INTERVAL '8 hours'),

  -- Depth 6: member-002 replies to depth 5
  ('at://did:plc:staging-member-002/forum.barazo.reply.post/3seeddeep06',
   '3seeddeep06', 'did:plc:staging-member-002',
   'That helped a lot, thanks! But now the firehose consumer is lagging behind.',
   'at://did:plc:staging-member-001/forum.barazo.topic.post/3seed009', 'bafyseed-t09',
   'at://did:plc:staging-moderator-001/forum.barazo.reply.post/3seeddeep05', 'bafyseed-d05',
   :community_did, 'bafyseed-d06', 6, NOW() - INTERVAL '7 hours'),

  -- Depth 7: admin replies to depth 6
  ('at://did:plc:staging-admin-001/forum.barazo.reply.post/3seeddeep07',
   '3seeddeep07', 'did:plc:staging-admin-001',
   'The firehose needs dedicated resources. Consider running it as a separate service.',
   'at://did:plc:staging-member-001/forum.barazo.topic.post/3seed009', 'bafyseed-t09',
   'at://did:plc:staging-member-002/forum.barazo.reply.post/3seeddeep06', 'bafyseed-d06',
   :community_did, 'bafyseed-d07', 7, NOW() - INTERVAL '6 hours 30 minutes'),

  -- Depth 8: member-003 replies to depth 7
  ('at://did:plc:staging-member-003/forum.barazo.reply.post/3seeddeep08',
   '3seeddeep08', 'did:plc:staging-member-003',
   'Separate service means another container though. The Pi is already running 4.',
   'at://did:plc:staging-member-001/forum.barazo.topic.post/3seed009', 'bafyseed-t09',
   'at://did:plc:staging-admin-001/forum.barazo.reply.post/3seeddeep07', 'bafyseed-d07',
   :community_did, 'bafyseed-d08', 8, NOW() - INTERVAL '6 hours'),

  -- Depth 9: mod replies to depth 8
  ('at://did:plc:staging-moderator-001/forum.barazo.reply.post/3seeddeep09',
   '3seeddeep09', 'did:plc:staging-moderator-001',
   'You could use a lightweight process manager instead of Docker for some services.',
   'at://did:plc:staging-member-001/forum.barazo.topic.post/3seed009', 'bafyseed-t09',
   'at://did:plc:staging-member-003/forum.barazo.reply.post/3seeddeep08', 'bafyseed-d08',
   :community_did, 'bafyseed-d09', 9, NOW() - INTERVAL '5 hours'),

  -- Depth 10: member-001 (topic author) replies to depth 9
  ('at://did:plc:staging-member-001/forum.barazo.reply.post/3seeddeep10',
   '3seeddeep10', 'did:plc:staging-member-001',
   'PM2 or systemd? I tried PM2 but it added 100MB of memory overhead.',
   'at://did:plc:staging-member-001/forum.barazo.topic.post/3seed009', 'bafyseed-t09',
   'at://did:plc:staging-moderator-001/forum.barazo.reply.post/3seeddeep09', 'bafyseed-d09',
   :community_did, 'bafyseed-d10', 10, NOW() - INTERVAL '4 hours 30 minutes'),

  -- Depth 11: admin replies to depth 10
  ('at://did:plc:staging-admin-001/forum.barazo.reply.post/3seeddeep11',
   '3seeddeep11', 'did:plc:staging-admin-001',
   'systemd is the way to go. Zero overhead and it handles restarts natively.',
   'at://did:plc:staging-member-001/forum.barazo.topic.post/3seed009', 'bafyseed-t09',
   'at://did:plc:staging-member-001/forum.barazo.reply.post/3seeddeep10', 'bafyseed-d10',
   :community_did, 'bafyseed-d11', 11, NOW() - INTERVAL '4 hours'),

  -- Depth 12: member-002 replies to depth 11
  ('at://did:plc:staging-member-002/forum.barazo.reply.post/3seeddeep12',
   '3seeddeep12', 'did:plc:staging-member-002',
   'Good call. One more question -- how do you handle SSL termination?',
   'at://did:plc:staging-member-001/forum.barazo.topic.post/3seed009', 'bafyseed-t09',
   'at://did:plc:staging-admin-001/forum.barazo.reply.post/3seeddeep11', 'bafyseed-d11',
   :community_did, 'bafyseed-d12', 12, NOW() - INTERVAL '3 hours'),

  -- Depth 13: mod replies to depth 12
  ('at://did:plc:staging-moderator-001/forum.barazo.reply.post/3seeddeep13',
   '3seeddeep13', 'did:plc:staging-moderator-001',
   'Caddy is perfect for this. Auto-HTTPS with minimal config and low resource usage.',
   'at://did:plc:staging-member-001/forum.barazo.topic.post/3seed009', 'bafyseed-t09',
   'at://did:plc:staging-member-002/forum.barazo.reply.post/3seeddeep12', 'bafyseed-d12',
   :community_did, 'bafyseed-d13', 13, NOW() - INTERVAL '2 hours 30 minutes'),

  -- Depth 14: member-003 replies to depth 13
  ('at://did:plc:staging-member-003/forum.barazo.reply.post/3seeddeep14',
   '3seeddeep14', 'did:plc:staging-member-003',
   'Has anyone benchmarked Caddy vs nginx on ARM? Curious about the TLS handshake overhead.',
   'at://did:plc:staging-member-001/forum.barazo.topic.post/3seed009', 'bafyseed-t09',
   'at://did:plc:staging-moderator-001/forum.barazo.reply.post/3seeddeep13', 'bafyseed-d13',
   :community_did, 'bafyseed-d14', 14, NOW() - INTERVAL '2 hours'),

  -- Depth 15: member-001 (topic author) wraps it up
  ('at://did:plc:staging-member-001/forum.barazo.reply.post/3seeddeep15',
   '3seeddeep15', 'did:plc:staging-member-001',
   'This whole thread is gold. Someone should turn this into a self-hosting guide.',
   'at://did:plc:staging-member-001/forum.barazo.topic.post/3seed009', 'bafyseed-t09',
   'at://did:plc:staging-member-003/forum.barazo.reply.post/3seeddeep14', 'bafyseed-d14',
   :community_did, 'bafyseed-d15', 15, NOW() - INTERVAL '1 hour')
ON CONFLICT DO NOTHING;
SQL
echo "  Deep thread created (15 levels)."

# --- Moderation Data ---
echo "Creating moderation data..."
run_psql <<'SQL'
-- Word filter: add sample words to community settings
UPDATE community_settings
SET word_filter = '["spam", "scam", "free money", "buy now"]'::jsonb
WHERE community_did = :community_did;

-- Moderation action log: record the pin, lock, and a topic deletion
INSERT INTO moderation_actions (action, target_uri, moderator_did, community_did, reason, created_at)
VALUES
  ('pin',
   'at://did:plc:staging-admin-001/forum.barazo.topic.post/3seed001',
   'did:plc:staging-admin-001', :community_did,
   'Pinned forum-wide as welcome announcement',
   NOW() - INTERVAL '7 days'),
  ('pin',
   'at://did:plc:staging-admin-001/forum.barazo.topic.post/3seed002',
   'did:plc:staging-moderator-001', :community_did,
   'Pinned in feedback category for visibility',
   NOW() - INTERVAL '6 days'),
  ('lock',
   'at://did:plc:staging-admin-001/forum.barazo.topic.post/3seed002',
   'did:plc:staging-moderator-001', :community_did,
   'Locked to keep bug reporting instructions stable',
   NOW() - INTERVAL '6 days'),
  ('delete',
   'at://did:plc:staging-member-003/forum.barazo.topic.post/3seedmod01',
   'did:plc:staging-moderator-001', :community_did,
   'Removed spam content',
   NOW() - INTERVAL '2 days')
ON CONFLICT DO NOTHING;

-- Moderation queue: sample items in different states
-- 1. Pending item (word filter match) - a reply that's waiting for review
INSERT INTO moderation_queue (content_uri, content_type, author_did, community_did, queue_reason, matched_words, status, created_at)
VALUES
  ('at://did:plc:staging-member-003/forum.barazo.reply.post/3seedheld01',
   'reply', 'did:plc:staging-member-003', :community_did,
   'word_filter', '["free money"]',
   'pending', NOW() - INTERVAL '3 hours')
ON CONFLICT DO NOTHING;

-- 2. Approved item (first post by new user)
INSERT INTO moderation_queue (content_uri, content_type, author_did, community_did, queue_reason, status, reviewed_by, created_at, reviewed_at)
VALUES
  ('at://did:plc:staging-member-002/forum.barazo.topic.post/3seed005',
   'topic', 'did:plc:staging-member-002', :community_did,
   'first_post',
   'approved', 'did:plc:staging-moderator-001',
   NOW() - INTERVAL '4 days', NOW() - INTERVAL '4 days' + INTERVAL '15 minutes')
ON CONFLICT DO NOTHING;

-- 3. Rejected item (word filter match on a deleted topic)
INSERT INTO moderation_queue (content_uri, content_type, author_did, community_did, queue_reason, matched_words, status, reviewed_by, created_at, reviewed_at)
VALUES
  ('at://did:plc:staging-member-003/forum.barazo.topic.post/3seedmod01',
   'topic', 'did:plc:staging-member-003', :community_did,
   'word_filter', '["scam", "buy now"]',
   'rejected', 'did:plc:staging-moderator-001',
   NOW() - INTERVAL '2 days', NOW() - INTERVAL '2 days' + INTERVAL '30 minutes')
ON CONFLICT DO NOTHING;
SQL
echo "  Moderation data created (word filter, action log, queue items)."

echo ""
echo "Staging seed complete."
echo ""
echo "Test users:"
echo "  Admin:     did:plc:staging-admin-001     (staging-admin.bsky.social)"
echo "  Moderator: did:plc:staging-moderator-001 (staging-mod.bsky.social)"
echo "  Member:    did:plc:staging-member-001    (staging-member.bsky.social)"
echo "  Member 2:  did:plc:staging-member-002    (staging-member2.bsky.social)"
echo "  Member 3:  did:plc:staging-member-003    (staging-member3.bsky.social)"
echo ""
echo "Categories: 5 top-level + 7 subcategories (12 total)"
echo "Topics: 10 | Flat replies: 18 | Deep thread: 15 replies (depth 1-15)"
echo "Pinned: 'Welcome' (forum-wide) + 'How to report bugs' (category, locked)"
echo "Moderation: 3 queue items (1 pending, 1 approved, 1 rejected) + 4 action log entries"
echo "Word filter: spam, scam, free money, buy now"
echo ""
echo "Deep thread topic: 'Self-hosting Barazo on a Raspberry Pi'"
