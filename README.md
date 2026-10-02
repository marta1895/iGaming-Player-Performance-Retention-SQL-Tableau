# iGaming-Player-Performance-Retention-SQL-Tableau-
In this project I analysed data from an online casino.
I prepared the data in SQL and built two dashboards in Tableau:
one for general business metrics and one for player retention.
 
> The data is confidential, so the database and the Tableau file are not shared.
> You can see the dashboards in the screenshots and the full SQL in `sql/analysis.sql`.
 
---
 
## Goal
 
1. **General Performance Dashboard**: show the main business metrics (registrations, deposits, withdrawals,
   GGR, NGR, bonuses, fees, active players) and conversions, with filters by time, referrer and country.
2. **Retention Dashboard**: show how many players keep depositing month after month.
All money is in EUR. All dates are in UTC.
 
## Data
 
| Table | Rows | What's inside |
|---|---|---|
| `user` | 1,750 | user status, type, referrer, registration time |
| `user_settings` | 1,750 | country of each user |
| `transactions` | 10,449 | deposits, withdrawals and bonuses |
| `bet_results` | 1,450,515 | every bet: amount, currency, profit, win or loss |
 
Period: April 2024 – August 2026.
 
## Tools
 
- **MySQL** and **DBeaver**: SQL queries
- **Tableau**: dashboards
## How I worked
 
1. Looked at the tables, columns and how the tables are connected.
2. Set the data rules: only valid users (status 5, type 0) and only successful transactions.
3. Built 3 tables in SQL.
4. Checked the numbers in every table.
5. Built the dashboards in Tableau.
6. Found something unusual in the retention data and checked why it happens.
## SQL tables
 
All tables start from the same list of valid users, so the filters are written only once.
 
**1. `dashboard_daily`**
One row per day, referrer and country. It has only counts and sums, so Tableau can filter and add them up correctly.
First and second deposits are found with `ROW_NUMBER()`.
 
**2. `user_cohorts`**
One row per user: registration month, date of the first deposit and date of the second deposit.
Used for the conversion charts.
 
**3. `retention`**
One row per user per month when they made a deposit.
It shows the month of the first deposit and how many months have passed since then.
 
## Metrics
 
| Metric | How it's calculated |
|---|---|
| FTD / STD | first / second successful deposit of a user |
| Reg → FTD | % of registered users who made a first deposit |
| FTD → STD | % of users with a first deposit who made a second one |
| Rough GGR | deposits − withdrawals |
| Turnover | sum of all bets |
| Win Sum | money paid for won bets (bet + profit), converted to EUR |
| GGR | turnover − win sum |
| Hold % | GGR ÷ turnover |
| Bonus Sum | deposit bonuses + loyalty bonuses |
| Transaction Fee | 1% crypto deposits, 0.5% crypto withdrawals, 3% fiat deposits and withdrawals |
| NGR | GGR − bonuses |
| NR | NGR − transaction fees |
| Active Players | average number of different players per day |
| Deposit Success Rate | successful deposits ÷ all deposit attempts |
| Retention | % of players who made a deposit N months after their first deposit |
 
## Dashboards
 
### General Performance
- Table with all metrics. You can switch it by month, referrer or country.
- Deposit success rate by month
- Registration → first deposit conversion
- First → second deposit conversion
![General Performance Dashboard]<img width="2398" height="1918" alt="General Performance Dashboard" src="https://github.com/user-attachments/assets/8b04f068-b3dd-49d1-8cd6-9d48c73dec12" />

 
### Retention
- Heat map: each row is a group of players who made their first deposit in the same month,
  each column is a month after that.
- Bar chart: how many players came back in the first 3 months, by referrer.
![Retention Dashboard]<img width="1758" height="1598" alt="Retention" src="https://github.com/user-attachments/assets/6242817b-b9e5-4991-97de-3041d40047e8" />

 
## Main findings
 
1. The casino keeps about **4%** of all bets (GGR ≈ €121K from ≈ €3.0M in bets).
2. About **9%** of registered users made a first deposit (162 of 1,750).
3. The biggest group of players (May 2024) has the lowest retention.
   59% of them came from referrer **96735**, and only **10%** of this referrer's players came back.
4. Referrer **112670** is the opposite: **61%** of its players came back,
   almost twice as many as players without a referrer (**35%**).
So the quality of players depends a lot on where they come from.
The groups are small (5–37 players), so this is a clear trend, not an exact number.
 
## How I checked the numbers
 
- Counted rows in every table after loading the data.
- Calculated GGR in two different ways and got the same result.
- Checked that totals (registrations, first and second deposits) are the same in all tables.
- Checked that the retention table has no duplicates.
  This check found a real mistake once: the table was doubled, and I fixed it.
## Limitations
 
- Users registered only on 1–2 days each month, so registrations are shown by month.
- After October 2024 the groups have fewer than 5 players, so their percentages are not reliable.
- Conversions are shown in charts, not in the main table,
  because in daily data they could go above 100%.
- Active players are shown as a daily average, because the same player would be counted many times otherwise.
## Next steps
 
- Check the quality of players from referrer 96735 before spending more money on it.
- Find out why players from referrer 112670 come back more often.
- Add monthly unique players to the dashboard.
## Repository structure
 
```
├── README.md
├── sql/
│   └── analysis.sql      # SQL tables, analysis and checks
└── images/
    ├── general_performance.png
    └── retention.png
```
 
---
 
**Author:** Marta Narozhnyak
 
