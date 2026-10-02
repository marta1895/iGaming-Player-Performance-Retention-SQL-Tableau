-- ----------------------------------------------------------
-- 1.1 GENERAL DASHBOARD: daily metrics table (dashboard_daily)
-- One row per day + referrer + country. Counts and sums only.
-- ----------------------------------------------------------
-- Ratios, averages and GGR/NGR/NR are calculated later in Tableau,
-- here I keep only counts and sums so they can be added up by any filter.

-- All dates in UTC
SET time_zone = '+00:00';

-- base cte: only status 5 and type 0 (rule from the task description).
-- Users without referrer are labeled as 'Organic'.
-- All other CTEs join to this one, so the user filter is written only once.
DROP TABLE IF EXISTS dashboard_daily;

CREATE TABLE dashboard_daily AS
WITH base AS (
	SELECT
		u.id,
		CASE WHEN u.referrer IS NULL OR TRIM(u.referrer) = '' THEN 'Organic' -- null/empty referrer replacing with Organic
			ELSE u.referrer
		END AS referrer,
		us.country_code AS country,
		FROM_UNIXTIME(u.created_at) AS registered_at -- created_at is stored in unix time
	FROM user u
	LEFT JOIN user_settings us ON u.id = us.user_id
	WHERE u.status = 5 AND u.type = 0
),
-- Registrations per day, referrer and country
registr AS (
	SELECT
		DATE(registered_at) AS day,
		referrer,
		country,
		COUNT(id) AS registrations
	FROM base
	GROUP BY day, referrer, country
),
-- All successful deposits (type 0, status 2).
-- rn = order of deposit for each user: 1 = first deposit, 2 = second one.
-- id is added to ORDER BY in case two deposits have the same time.
deposit AS (
	SELECT
		t.id,
		t.is_fiat,
		t.in_eur,
		t.user_id,
		t.created_at,
		b.referrer,
		b.country,
		ROW_NUMBER() OVER (PARTITION BY t.user_id ORDER BY t.created_at, t.id) AS rn
	FROM transactions t
	JOIN base b ON b.id = t.user_id -- inner join removes users that are not in base
	WHERE t.type = 0 AND t.status = 2
),
-- FTD: first deposit of each user, counted on the day it was made
ftd AS (
	SELECT
		DATE(created_at) AS day,
		referrer,
		country,
		COUNT(*) AS ftd_cnt,
		SUM(in_eur) AS ftd_sum
	FROM deposit
	WHERE rn = 1
	GROUP BY day, referrer, country
),
-- STD: second deposit of each user, counted on the day it was made
std AS (
	SELECT
		DATE(created_at) AS day,
		referrer,
		country,
		COUNT(*) AS std_cnt,
		SUM(in_eur) AS std_sum
	FROM deposit
	WHERE rn = 2
	GROUP BY day, referrer, country
),
-- All successful deposits + deposit fee (crypto 1%, fiat 3%)
total_deposits AS (
	SELECT
		DATE(created_at) AS day,
		referrer,
		country,
		SUM(CASE WHEN is_fiat = 0 THEN in_eur * 0.01 -- crypto
         		WHEN is_fiat = 1 THEN in_eur * 0.03 -- fiat
    	END) AS deposit_fee,
		COUNT(*) AS total_deposit_cnt,
		SUM(in_eur) AS total_deposit_sum
	FROM deposit
	GROUP BY day, referrer, country
),
-- All successful withdrawals (type 1, status 2)
withdrawals AS (
	SELECT
		t.id,
		t.is_fiat,
		t.in_eur,
		t.user_id,
		t.created_at,
		b.referrer,
		b.country
	FROM transactions t
	JOIN base b ON b.id = t.user_id
	WHERE t.type = 1 AND t.status = 2
),
-- Withdrawals count, sum and fee (crypto 0.5%, fiat 3%)
withdrawals_metrics AS (
	SELECT
		DATE(created_at) AS day,
		referrer,
		country,
		SUM(CASE WHEN is_fiat = 0 THEN in_eur * 0.005 -- crypto
         		WHEN is_fiat = 1 THEN in_eur * 0.03 -- fiat
    	END) AS withdrawal_fee,
		COUNT(*) AS withdrawal_cnt,
		SUM(in_eur) AS withdrawal_sum
	FROM withdrawals
	GROUP BY day, referrer, country
),
-- All deposit attempts (rejected + successful).
-- Needed for Deposits Success Rate = deposit_cnt / deposit_attempt_cnt
deposit_attempts AS (
	SELECT
		DATE(t.created_at) AS day,
		b.referrer,
		b.country,
		COUNT(*) AS deposit_attempt_cnt
	FROM transactions t
	JOIN base b ON b.id = t.user_id
	WHERE t.type = 0 AND t.status IN (1, 2)
	GROUP BY day, b.referrer, b.country
),
-- Successful bonuses: type 4 = deposit bonus, type 20 = loyalty bonus
bonuses AS (
	SELECT
		DATE(t.created_at) AS day,
		b.referrer,
		b.country,
		SUM(CASE WHEN t.type = 4  THEN t.in_eur END) AS deposit_bonus_sum,
		SUM(CASE WHEN t.type = 20 THEN t.in_eur END) AS loyalty_bonus_sum
	FROM transactions t
	JOIN base b ON b.id = t.user_id
	WHERE t.status = 2 AND t.type IN (4, 20)
	GROUP BY day, b.referrer, b.country
),
-- Bets: turnover, win sum and active players.
-- profit is in bet currency, so I convert payout (bet + profit) to EUR with in_eur / bet.
bet_metrics AS (
	SELECT
		DATE(br.created_at) AS day,
		b.referrer,
		b.country,
		SUM(br.in_eur) AS bet_sum,
		SUM(CASE WHEN br.is_win = 1
				THEN br.in_eur * (br.bet + br.profit) / NULLIF(br.bet, 0) -- NULLIF avoids division by zero if a bet of 0 exists
		END) AS win_sum,
		COUNT(DISTINCT br.user_id) AS active_players -- unique players per day
	FROM bet_results br
	JOIN base b ON b.id = br.user_id
	GROUP BY day, b.referrer, b.country
),
-- List of all day + referrer + country combinations that have any activity.
-- UNION instead of UNION ALL since it removes duplicate keys, so each combination appears exactly once
all_keys AS (
	SELECT day, referrer, country FROM registr
	UNION SELECT day, referrer, country FROM ftd
	UNION SELECT day, referrer, country FROM std
	UNION SELECT day, referrer, country FROM total_deposits
	UNION SELECT day, referrer, country FROM withdrawals_metrics
	UNION SELECT day, referrer, country FROM deposit_attempts
	UNION SELECT day, referrer, country FROM bonuses
	UNION SELECT day, referrer, country FROM bet_metrics
)
-- Final table: every metric joined to the list of combinations,
-- LEFT JOIN so no row is lost, empty values replaced with 0
SELECT
	k.day,
	k.referrer,
	k.country,
	COALESCE(r.registrations, 0)        AS registrations,
	COALESCE(f.ftd_cnt, 0)              AS ftd_cnt,
	COALESCE(f.ftd_sum, 0)              AS ftd_sum,
	COALESCE(s.std_cnt, 0)              AS std_cnt,
	COALESCE(s.std_sum, 0)              AS std_sum,
	COALESCE(d.total_deposit_cnt, 0)    AS deposit_cnt,
	COALESCE(d.total_deposit_sum, 0)    AS deposit_sum,
	COALESCE(d.deposit_fee, 0)          AS deposit_fee,
	COALESCE(da.deposit_attempt_cnt, 0) AS deposit_attempt_cnt,
	COALESCE(w.withdrawal_cnt, 0)       AS withdrawal_cnt,
	COALESCE(w.withdrawal_sum, 0)       AS withdrawal_sum,
	COALESCE(w.withdrawal_fee, 0)       AS withdrawal_fee,
	COALESCE(bo.deposit_bonus_sum, 0)   AS deposit_bonus_sum,
	COALESCE(bo.loyalty_bonus_sum, 0)   AS loyalty_bonus_sum,
	COALESCE(bm.bet_sum, 0)             AS bet_sum,
	COALESCE(bm.win_sum, 0)             AS win_sum,
	COALESCE(bm.active_players, 0)      AS active_players
FROM all_keys k
LEFT JOIN registr r              USING (day, referrer, country)
LEFT JOIN ftd f                  USING (day, referrer, country)
LEFT JOIN std s                  USING (day, referrer, country)
LEFT JOIN total_deposits d       USING (day, referrer, country)
LEFT JOIN withdrawals_metrics w  USING (day, referrer, country)
LEFT JOIN deposit_attempts da    USING (day, referrer, country)
LEFT JOIN bonuses bo             USING (day, referrer, country)
LEFT JOIN bet_metrics bm         USING (day, referrer, country)
ORDER BY k.day, k.referrer, k.country;


-- ----------------------------------------------------------
-- 1.2 GENERAL DASHBOARD: user-level table (user_cohorts)
-- One row per user: registration month, first and second
-- deposit dates. Used for Reg2Dep and FTD2STD charts.
-- ----------------------------------------------------------

DROP TABLE IF EXISTS user_cohorts;

CREATE TABLE user_cohorts (
	user_id   INT,
	referrer  VARCHAR(50),
	country   VARCHAR(10),
	reg_month DATE,
	ftd_date  DATETIME NULL,
	std_date  DATETIME NULL
);

SET time_zone = '+00:00';

INSERT INTO user_cohorts
-- same base cte: same rules as in dashboard_daily (status 5, type 0)
WITH base AS (
	SELECT
		u.id,
		CASE WHEN u.referrer IS NULL OR TRIM(u.referrer) = '' THEN 'Organic'
			ELSE u.referrer
		END AS referrer,
		us.country_code AS country,
		FROM_UNIXTIME(u.created_at) AS registered_at
	FROM user u
	LEFT JOIN user_settings us ON u.id = us.user_id
	WHERE u.status = 5 AND u.type = 0
),
-- Successful deposits numbered per user (1 = first, 2 = second)
deposit AS (
	SELECT
		t.user_id,
		DATE(t.created_at) AS created_at,
		ROW_NUMBER() OVER (PARTITION BY t.user_id ORDER BY t.created_at, t.id) AS rn
	FROM transactions t
	JOIN base b ON b.id = t.user_id
	WHERE t.type = 0 AND t.status = 2
),
-- First deposit of each user
ftd AS (
	SELECT user_id, created_at AS ftd_date
	FROM deposit
	WHERE rn = 1
),
-- Second deposit of each user
std AS (
	SELECT user_id, created_at AS std_date
	FROM deposit
	WHERE rn = 2
)
-- One row per user; LEFT JOIN keeps users without deposits (dates are NULL)
SELECT
	b.id AS user_id,
	b.referrer,
	b.country,
	DATE(DATE_FORMAT(b.registered_at, '%Y-%m-01')) AS reg_month,
	f.ftd_date,
	s.std_date
FROM base b
LEFT JOIN ftd f ON f.user_id = b.id
LEFT JOIN std s ON s.user_id = b.id;


-- ----------------------------------------------------------
-- 2.1 RETENTION DASHBOARD: retention table (retention)
-- One row per user per month with a deposit.
-- Cohort = month of first deposit (FTD month).
-- ----------------------------------------------------------

DROP TABLE IF EXISTS retention;

CREATE TABLE retention (
	user_id       INT,
	referrer      VARCHAR(50),
	country       VARCHAR(10),
	ftd_month     DATE,
	deposit_month DATE,
	month_number  INT
);

SET time_zone = '+00:00';

INSERT INTO retention
WITH base AS (
	SELECT
		u.id,
		CASE WHEN u.referrer IS NULL OR TRIM(u.referrer) = '' THEN 'Organic'
			ELSE u.referrer
		END AS referrer,
		us.country_code AS country,
		FROM_UNIXTIME(u.created_at) AS registered_at
	FROM user u
	LEFT JOIN user_settings us ON u.id = us.user_id
	WHERE u.status = 5 AND u.type = 0
),
-- All successful deposits (type 0 = deposit, status 2 = success) of valid users
deposit AS (
	SELECT
		t.user_id,
		DATE(t.created_at) AS created_at
	FROM transactions t
	JOIN base b ON b.id = t.user_id
	WHERE t.type = 0 AND t.status = 2
),
-- Months in which each user made at least one deposit
-- one row per user per month, even if there were several deposits
deposit_months AS (
	SELECT DISTINCT
		d.user_id,
		b.referrer,
		b.country,
		DATE(DATE_FORMAT(d.created_at, '%Y-%m-01')) AS deposit_month
	FROM deposit d
	JOIN base b ON b.id = d.user_id
)
-- ftd_month = first month with a deposit (the cohort)
-- month_number = how many months after the FTD month (0 = FTD month)
SELECT
	user_id,
	referrer,
	country,
	MIN(deposit_month) OVER (PARTITION BY user_id) AS ftd_month,
	deposit_month,
	TIMESTAMPDIFF(MONTH, MIN(deposit_month) OVER (PARTITION BY user_id), deposit_month) AS month_number
FROM deposit_months;

-- ----------------------------------------------------------
-- 2.2 ADDITIONAL ANALYSIS: why cohorts retain differently
-- ----------------------------------------------------------

-- Question: which referrers did users in each cohort come from?
-- Only cohorts up to Oct 2024 (later cohorts have fewer than 5 users)
SELECT ftd_month, referrer, COUNT(*) AS ftd_users
FROM retention
WHERE month_number = 0
  AND ftd_month <= '2024-10-01'
GROUP BY ftd_month, referrer
ORDER BY ftd_month, ftd_users DESC;
-- Result summary:
-- Most cohorts have users from many small referrers plus organic users
-- (organic users are in every month).
-- May 2024 is different: 26 of 44 users (59%) came from one referrer, 96735.
-- This referrer is almost absent in other months.
-- In Aug-Oct 2024, most users came from referrer 112670 (17 users) and organic.
-- May 2024 has the lowest retention and Aug-Oct the highest,
-- so the referrer could be the reason. I check this in the next query.


-- Question: do users from different referrers come back at different rates?
-- Only referrers with 5+ FTD users
SELECT
	referrer,
	COUNT(DISTINCT user_id) AS ftd_users,
	COUNT(DISTINCT CASE WHEN month_number BETWEEN 1 AND 3 THEN user_id END) AS retained_m1_3,
	ROUND(100 * COUNT(DISTINCT CASE WHEN month_number BETWEEN 1 AND 3 THEN user_id END)
		/ COUNT(DISTINCT user_id), 1) AS retention_m1_3_pct
FROM retention
GROUP BY referrer
HAVING ftd_users >= 5
ORDER BY ftd_users DESC;
-- Result summary:
-- Players from different referrers come back at very different rates
-- (% of users who deposited again 1-3 months after their first deposit).
-- Organic users: 35%. This is the normal level to compare with.
-- Referrer 112670: 61%, almost twice as many as organic users.
-- Most users in the good Aug-Oct 2024 cohorts came from this referrer.
-- Referrer 96735: only 10%. Most users in the May 2024 cohort came from here,
-- so this is why the biggest cohort has the lowest retention.
-- Referrer 100545: none of its 7 users came back.
-- Note: the groups are small (5-37 users), so the numbers show a clear trend, not exact values.