-- 등록 채굴 기능(0031) 이전에 올라온 판매중 상품에 등록 채굴을 소급 지급한다.
-- 원화 상품: 가격 ÷ 10 ÷ 10원 = 가격/100 QTA, 상품당 최대 1,000. 다시 돌려도 중복 지급 없음.
-- 거래완료(sold)·이미 지급된 상품은 제외. 하루 상한은 적용하지 않는다 (일회성 소급).
INSERT OR IGNORE INTO qta_ledger (id, user_id, amount, reason, idem_key, meta)
SELECT lower(hex(randomblob(16))), seller_id, MIN(1000, price / 100), 'listing_reward',
       'listing_reward:' || id,
       json_object('product_id', id, 'title', title, 'price', price, 'currency', 'KRW', 'backfill', 1)
  FROM products
 WHERE listing_reward = 0 AND price >= 100 AND market = 'kr' AND status <> 'sold';

UPDATE users SET qta_balance = qta_balance + (
  SELECT COALESCE(SUM(l.amount), 0) FROM qta_ledger l
    JOIN products p ON l.idem_key = 'listing_reward:' || p.id
   WHERE p.seller_id = users.id AND p.listing_reward = 0 AND p.market = 'kr'
     AND p.status <> 'sold' AND p.price >= 100 AND l.reason = 'listing_reward'
), updated_at = datetime('now')
WHERE id IN (SELECT seller_id FROM products
              WHERE listing_reward = 0 AND price >= 100 AND market = 'kr' AND status <> 'sold');

UPDATE products SET listing_reward = MIN(1000, price / 100)
 WHERE listing_reward = 0 AND price >= 100 AND market = 'kr' AND status <> 'sold'
   AND EXISTS (SELECT 1 FROM qta_ledger WHERE idem_key = 'listing_reward:' || products.id);
