-- Eggplant 🍆 - Add video_url column to products
-- Allows sellers to attach a video (YouTube link OR uploaded video stored in R2)

ALTER TABLE products ADD COLUMN video_url TEXT DEFAULT '';
