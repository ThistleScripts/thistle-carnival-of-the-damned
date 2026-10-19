-- Carnival of the Damned - migration 002: attraction registry seed
-- INSERT IGNORE keeps this idempotent.

INSERT IGNORE INTO carnival_attractions (id, label, staff_judged, created_at) VALUES
    ('shooting', 'The Shooting Gallery', 0, UNIX_TIMESTAMP()),
    ('wheel', 'The Wheel of Misfortune', 0, UNIX_TIMESTAMP()),
    ('fortune', 'The Fortune Teller''s Curse', 0, UNIX_TIMESTAMP()),
    ('puppets', 'The Puppet Master''s Theatre', 1, UNIX_TIMESTAMP()),
    ('deception', 'The Hall of Deception', 1, UNIX_TIMESTAMP()),
    ('horror', 'The House of Horrors', 0, UNIX_TIMESTAMP());
