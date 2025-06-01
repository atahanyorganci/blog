---
title: Self Join Elimination
---

In business analytics, queries that calculate running totals, rankings, or lag/lead values are essential for uncovering trends and insights within data. One common way to write these queries is by using a self-join, where a table is joined with itself to compare or aggregate rows based on certain conditions. While self-joins can achieve the desired results, they often introduce significant inefficiencies. By recognizing these patterns, we can optimize such queries by rewriting self-joins as window function operations, leading to better performance and reduced computational overhead.

## Running Total using Self Join

Let’s assume there is a `purchases` table with columns related the purchase amount, date and also user who made the purchase.

```sql
SELECT a.user_id, a.purchase_date, SUM(b.amount) AS running_total
FROM purchases a
JOIN purchases b ON a.user_id = b.user_id AND b.purchase_date <= a.purchase_date
GROUP BY a.user_id, a.purchase_date;
```

Since `purchases.user_id` is not a unique value, for any given purchase by a user all of the purchases before it will be returned. For example given following query

```sql
SELECT *
FROM purchases a
JOIN purchases b ON a.user_id = b.user_id AND b.purchase_date <= a.purchase_date;
```

it will return

```text
| a.id | a.user_id | a.purchase_date | a.amount | b.id | b.user_id | b.purchase_date | b.amount |
| ---- | --------- | --------------- | -------- | ---- | --------- | --------------- | -------- |
| 3    | 1         | 2024-05-10      | 40.00    | 1    | 1         | 2024-05-01      | 50.00    |
| 3    | 1         | 2024-05-10      | 40.00    | 2    | 1         | 2024-05-03      | 25.00    |
| 3    | 1         | 2024-05-10      | 40.00    | 3    | 1         | 2024-05-10      | 40.00    |
| 2    | 1         | 2024-05-03      | 25.00    | 1    | 1         | 2024-05-01      | 50.00    |
| 2    | 1         | 2024-05-03      | 25.00    | 2    | 1         | 2024-05-03      | 25.00    |
| 1    | 1         | 2024-05-01      | 50.00    | 1    | 1         | 2024-05-01      | 50.00    |
```

Then, we can group these based `a.user_id` and `a.purchase_date` and compute the total purchases made by that customer until that date via summing over `b.amount`

One key observation here is number of rows processed by the query has `O(n^2)` complexity, simply we are iterating over all of the purchases to compute the total for each purchase. Goal of this optimization is to replace this and similar ones with a more efficient window functions.

## Optimizable Patterns

### Unique Keyed Self Join

Before moving on to window functions there is a simpler case where a similar optimization can be applied. Self join on a column(s) that form a unique key for the table. Consider the following SQL query.

```sql
SELECT a.id
FROM employees a
JOIN employees b ON a.id = b.id
WHERE b.department = 'HR';
```

This query performs a self-join on the `employees` table, filtering for employees in the `'HR'` department. Unoptimized logical plan for the query is simply as follows.

```
Projection: a.id
  Filter: b.department = Utf8("HR")
    Inner Join:  Filter: a.id = b.id
      SubqueryAlias: a
        TableScan: employees
      SubqueryAlias: b
        TableScan: employees
```

Since the join is on a unique key (`id`) and we are performing a inner join (null values will be discarded) for any given row on left hand side (`FROM employees a`) there only exist one and only one row on the right hand side (`JOIN employees b`) that will be returned.

In optimized case, we can eliminate the join, we can merge `TableScan`s together and perform filtering based on the `department`. Then, expected optimized output for the query should be as follows.

```
Projection: a.id
	Filter: a.department = Utf8("HR")
		SubqueryAlias: a
			TableScan: employees
```

#### Self Join with a Subquery

Similar optimizations can be done when right side of the join includes projections and/or filters.

```sql
SELECT a.id
FROM employees a
JOIN (SELECT id FROM employees WHERE department = 'HR') b ON a.id = b.id;
```

Unoptimized logical plan is

```
Projection: a.id
  Inner Join:  Filter: a.id = b.id
    SubqueryAlias: a
      TableScan: employees
    SubqueryAlias: b
      Projection: employees.id
        Filter: employees.department = Utf8("HR")
          TableScan: employees
```

by combing left and right side of the query we can have

```
Projection: a.id
  SubqueryAlias: b
    SubqueryAlias: a
      Projection: employees.id
        Filter: employees.department = Utf8("HR")
          TableScan: employees
```

Again, a following pass of the optimizer can eliminate redundant alises and projections.

### Running Total

As outlined in the introduction self-join queries can be used for computing running totals and other various aggreagation functions.

```sql
SELECT a.user_id, a.purchase_date, SUM(b.amount) AS running_total
FROM purchases a
JOIN purchases b ON a.user_id = b.user_id AND b.purchase_date <= a.purchase_date
GROUP BY a.user_id, a.purchase_date;
```

Unoptimized logical plan the for the query is as follows.

```
Projection: a.user_id, a.purchase_date, sum(b.amount) AS running_total
  Aggregate: groupBy=[[a.user_id, a.purchase_date]], aggr=[[sum(CAST(b.amount AS UInt64))]]
    Projection: a.user_id, a.purchase_date, b.amount
      Inner Join: a.user_id = b.user_id Filter: b.purchase_date <= a.purchase_date
        SubqueryAlias: a
          TableScan: purchases projection=[user_id, purchase_date]
        SubqueryAlias: b
          TableScan: purchases projection=[user_id, purchase_date, amount]
```

Let’s now bisect this query to derive the optimization rule.

- For this optimization join condition should **NOT** be a unique key for the table as it would make aggragtion function return the singular row.
- `GROUP BY ...` expressions become the partition key for the window expression.
- Join filter `AND b.purchase_date <= a.purchase_date` compares the same columns and should be not null.
  - `purchase_date` is column should be used for ordering, `ORDER BY purchase_date`
  - `<` ordering should be ascdending, `ASC`
  - `<=` means that window function should include the current row, `… AND CURRENT ROW`
- Lastly, update aggregation function expression `SUM(b.amount)` as `SUM(amount)` since `b` alias is removed/eliminated.

Putting it all together, expected optimized logical plan for the query can be written as follows.

```
Projection: a.user_id, a.purchase_date, running_total
  WindowAggr: windowExpr=[SUM(amount) OVER (PARTITION BY user_id ORDER BY purchase_date ASC NULLS LAST ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)]
    SubqueryAlias: a
      TableScan: purchases projection=[user_id, purchase_date, amount]
```

With this rewrite allows using an window function that grows linearly with input table size instead of quadratically when self-join is used.

### Non-Optimizable Pattern

Window expression optimization relies on the fact that columns being compared are the same.

```sql
SELECT a.id, a.amount, b.amount
FROM purchases a
JOIN purchases b ON a.user_id = b.user_id AND b.purchase_date <= a.amount;
```

In this case, the query compares values across different rows (`b.purchase_date <= a.amount`), which cannot be represented using standard window functions. Therefore, this self-join should not be eliminated.
