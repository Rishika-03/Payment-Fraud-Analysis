-- ============================================================
-- IEEE-CIS Fraud Detection — Business Analysis Queries
-- Author: Rishika Sinha
-- Dataset: 590,540 transactions | 3.5% baseline fraud rate
-- ============================================================

-- 1. OVERALL FRAUD SUMMARY
SELECT
    COUNT(*)                                          AS total_transactions,
    SUM(isFraud)                                      AS total_fraud,
    ROUND(SUM(isFraud) * 100.0 / COUNT(*), 2)        AS fraud_rate_pct,
    ROUND(AVG(TransactionAmt), 2)                     AS avg_transaction_amt,
    ROUND(SUM(CASE WHEN isFraud = 1
        THEN TransactionAmt END), 2)                  AS total_fraud_value
FROM transactions;

-- 2. FRAUD RATE BY CARD NETWORK
-- Finding: Discover has 2x fraud rate vs Visa/Mastercard
SELECT
    card4                                             AS card_network,
    COUNT(*)                                          AS total_txns,
    SUM(isFraud)                                      AS fraud_txns,
    ROUND(SUM(isFraud) * 100.0 / COUNT(*), 2)        AS fraud_rate_pct
FROM transactions
WHERE card4 IS NOT NULL
GROUP BY card4
ORDER BY fraud_rate_pct DESC;

-- 3. HOURLY FRAUD PATTERN
-- Finding: 5am-9am is peak fraud window (up to 10.61% fraud rate)
SELECT
    (TransactionDT / 3600) % 24                      AS hour_of_day,
    COUNT(*)                                          AS total_txns,
    SUM(isFraud)                                      AS fraud_txns,
    ROUND(SUM(isFraud) * 100.0 / COUNT(*), 2)        AS fraud_rate_pct
FROM transactions
GROUP BY hour_of_day
ORDER BY fraud_rate_pct DESC
LIMIT 10;

-- 4. CREDIT VS DEBIT FRAUD COMPARISON
-- Finding: Credit cards have 2.7x higher fraud rate than debit
SELECT
    card6                                             AS card_type,
    COUNT(*)                                          AS total_txns,
    SUM(isFraud)                                      AS fraud_txns,
    ROUND(SUM(isFraud) * 100.0 / COUNT(*), 2)        AS fraud_rate_pct,
    ROUND(AVG(TransactionAmt), 2)                     AS avg_txn_amt
FROM transactions
WHERE card6 IN ('credit', 'debit')
GROUP BY card6
ORDER BY fraud_rate_pct DESC;

-- 5. TRANSACTION AMOUNT BUCKETS
-- Finding: Micro txns (<$25) have highest fraud rate — card testing behavior
SELECT
    CASE
        WHEN TransactionAmt < 25   THEN '0-25'
        WHEN TransactionAmt < 50   THEN '25-50'
        WHEN TransactionAmt < 100  THEN '50-100'
        WHEN TransactionAmt < 200  THEN '100-200'
        WHEN TransactionAmt < 500  THEN '200-500'
        WHEN TransactionAmt < 1000 THEN '500-1K'
        ELSE '1K+'
    END                                               AS amt_bucket,
    COUNT(*)                                          AS total_txns,
    SUM(isFraud)                                      AS fraud_txns,
    ROUND(SUM(isFraud) * 100.0 / COUNT(*), 2)        AS fraud_rate_pct
FROM transactions
GROUP BY amt_bucket
ORDER BY MIN(TransactionAmt);

-- 6. HIGH RISK EMAIL DOMAINS
-- Finding: outlook.com has 9.46% fraud rate vs 2.28% for yahoo.com
SELECT
    P_emaildomain                                     AS email_domain,
    COUNT(*)                                          AS total_txns,
    SUM(isFraud)                                      AS fraud_txns,
    ROUND(SUM(isFraud) * 100.0 / COUNT(*), 2)        AS fraud_rate_pct
FROM transactions
WHERE P_emaildomain IS NOT NULL
GROUP BY P_emaildomain
HAVING COUNT(*) > 1000
ORDER BY fraud_rate_pct DESC
LIMIT 10;

-- 7. DEVICE TYPE RISK ANALYSIS
-- Finding: Mobile = 10.17% vs Desktop = 6.52% fraud rate
SELECT
    DeviceType,
    COUNT(*)                                          AS total_txns,
    SUM(isFraud)                                      AS fraud_txns,
    ROUND(SUM(isFraud) * 100.0 / COUNT(*), 2)        AS fraud_rate_pct
FROM transactions
LEFT JOIN identity USING (TransactionID)
GROUP BY DeviceType
ORDER BY fraud_rate_pct DESC;

-- 8. MULTI-FACTOR HIGH RISK PROFILE
-- Finding: mobile + credit + 5-9am = 26.96% fraud rate (7.9x baseline)
SELECT
    CASE
        WHEN (TransactionDT/3600)%24 BETWEEN 5 AND 9
             AND card6 = 'credit'
             AND DeviceType = 'mobile'
        THEN 'High Risk Profile'
        ELSE 'Standard'
    END                                               AS risk_segment,
    COUNT(*)                                          AS total_txns,
    SUM(isFraud)                                      AS fraud_txns,
    ROUND(SUM(isFraud) * 100.0 / COUNT(*), 2)        AS fraud_rate_pct
FROM transactions
LEFT JOIN identity USING (TransactionID)
GROUP BY risk_segment
ORDER BY fraud_rate_pct DESC;

-- 9. STATISTICAL ANOMALY FLAGGING (Z-score > 3)
-- Flags transactions with abnormal amounts for review
SELECT
    TransactionID,
    TransactionAmt,
    isFraud,
    ROUND(
        ABS(TransactionAmt - AVG(TransactionAmt) OVER()) /
        NULLIF(STDDEV(TransactionAmt) OVER(), 0)
    , 2)                                              AS zscore,
    CASE
        WHEN ABS(TransactionAmt - AVG(TransactionAmt) OVER()) /
             NULLIF(STDDEV(TransactionAmt) OVER(), 0) > 3
        THEN 'ANOMALY'
        ELSE 'NORMAL'
    END                                               AS anomaly_flag
FROM transactions
ORDER BY zscore DESC
LIMIT 20;

-- 10. DAILY TRANSACTION TREND WITH 7-DAY ROLLING FRAUD RATE
-- Shows fraud rate trends over time using window functions
SELECT
    day_num,
    COUNT(*)                                          AS daily_txns,
    SUM(isFraud)                                      AS daily_fraud,
    ROUND(SUM(isFraud) * 100.0 / COUNT(*), 2)        AS daily_fraud_rate,
    ROUND(AVG(SUM(isFraud) * 100.0 / COUNT(*))
        OVER (ORDER BY day_num
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)
    , 2)                                              AS rolling_7day_fraud_rate
FROM (
    SELECT *, (TransactionDT / 86400) AS day_num
    FROM transactions
) t
GROUP BY day_num
ORDER BY day_num;
