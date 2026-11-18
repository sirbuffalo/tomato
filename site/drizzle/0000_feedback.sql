CREATE TABLE `feedback` (
  `id` text PRIMARY KEY NOT NULL,
  `created_at` text NOT NULL,
  `message` text NOT NULL,
  `handled_at` text
);
--> statement-breakpoint
CREATE INDEX `feedback_created_at_idx` ON `feedback` (`created_at`);
