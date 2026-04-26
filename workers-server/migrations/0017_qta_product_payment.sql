-- 0017_qta_product_payment.sql
--
-- 상품 거래에 QTA 결제 기능 추가.
--
-- 판매자가 상품을 등록할 때 선택적으로 'qta_price' (정수 QTA) 를 매길 수 있다.
--   - qta_price = NULL 또는 0 → KRW 거래 (현장 송금/계좌이체 등 외부 처리)
--   - qta_price > 0          → QTA 거래. 거래 완료 시점에 자동으로 buyer→seller
--                              잔액 이체 (멱등 키: trade_payment:<product_id>).
--
-- 가격 단위는 정수만 허용한다 (소수 QTA 없음).

ALTER TABLE products ADD COLUMN qta_price INTEGER NOT NULL DEFAULT 0;

-- qta_price 가 0 보다 큰 상품만 빠르게 골라 보기 위한 인덱스 (선택).
CREATE INDEX IF NOT EXISTS idx_products_qta_price
  ON products(qta_price) WHERE qta_price > 0;
