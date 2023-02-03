----------------------------------------------------------- E-COMMERCE-DATA-PROJECT -----------------------------------------------------------

--Introduction

-- You have to create a database and import into the given csv file. (You should research how to import a .csv file)

select * from dbo.e_commerce_data

--Analyze the data by finding the answers to the questions below:

--1. Find the top 3 customers who have the maximum count of orders.

select top 3 Cust_ID, count(Ord_ID) Order_ID_sum
from dbo.e_commerce_data
group by Cust_ID
order by Order_ID_sum desc


--2. Find the customer whose order took the maximum time to get shipping.

select top 1 Cust_ID, DaysTakenForShipping
from dbo.e_commerce_data
order by DaysTakenForShipping desc


--3. Count the total number of unique customers in January and how many of them came back every month over the entire year in 2011

select month(Order_Date) order_month,
		count(distinct Cust_ID) monthl_customer_counts
from dbo.e_commerce_data
where year(Order_Date) = 2011 
	and Cust_ID in (select distinct Cust_ID 
					from dbo.e_commerce_data
					where month(Order_Date) = 1 and year(Order_Date) = 2011)
group by month(Order_Date)


--4. Write a query to return for each user the time elapsed between the first purchasing and the third purchasing, in ascending order by Customer ID.

with t1 as (
	select *,
		row_number() over(partition by Cust_ID order by Order_Date) order_number,
		first_value(Order_Date) over(partition by Cust_ID order by Order_Date) first_order
	from dbo.e_commerce_data )
select Cust_ID, datediff(day, first_order, Order_Date) diff_order_dates
from t1
where order_number = 3
order by Cust_ID


--5. Write a query that returns customers who purchased both product 11 and product 14, 
--		as well as the ratio of these products to the total number of products purchased by the customer.

with t1 as(
	select distinct Cust_ID , sum(Order_Quantity) over(partition by Cust_ID) total_quantity,
		sum(case when Prod_ID = 'Prod_11' then Order_Quantity else 0 end) over(partition by Cust_ID) Prod_11_total_quantity,
		sum(case when Prod_ID = 'Prod_14' then Order_Quantity else 0 end) over(partition by Cust_ID) Prod_14_total_quantity
	from dbo.e_commerce_data 
	where  Cust_ID in ( select Cust_ID 
						from dbo.e_commerce_data
						where Prod_ID = 'Prod_11'  
						intersect
						select Cust_ID 
						from dbo.e_commerce_data
						where Prod_ID = 'Prod_14' )
)
select Cust_ID,
	cast(1.0 * prod_11_total_quantity / total_quantity as decimal(10,2)) ratio_Prod_11,
	cast(1.0 * prod_14_total_quantity / total_quantity as decimal(10,2)) ratio_Prod_14
from t1

--Customer Segmentation
--Categorize customers based on their frequency of visits. The following steps will guide you. If you want, you can track your own way.
--1. Create a “view” that keeps visit logs of customers on a monthly basis. (For each log, three field is kept: Cust_id, Year, Month)

create view visit_logs as
	select Cust_ID, 
		year(Order_Date) Order_year,
		month(Order_Date) Order_month
	from dbo.e_commerce_data

select * from visit_logs

--2. Create a “view” that keeps the number of monthly visits by users. (Show separately all months from the beginning business)

create view monthly_visit_number as
	select Cust_ID, year(Order_Date) Order_year, month(Order_Date) Order_month,
		count(Order_Date) monthly_visit_count
	from dbo.e_commerce_data
	group by Cust_ID, Order_Date, year(Order_Date), month(Order_Date) 
	
select * from monthly_visit_number

--3. For each visit of customers, create the next month of the visit as a separate column.

with t1 as(
	select Cust_ID, Order_Date,year(Order_Date) Order_year, month(Order_Date)Order_month,
		lead(Order_Date) over(partition by Cust_ID order by Order_Date) next_visit_date
	from dbo.e_commerce_data
) 
select *, 
	month(next_visit_date) next_visit_month
from t1

--4. Calculate the monthly time gap between two consecutive visits by each customer.

select * ,
	datediff(month, Order_Date, next_visit_date) time_gap
from (	select Cust_ID, Order_Date,year(Order_Date) [Year], month(Order_Date) [Month],
			lead(Order_Date) over(partition by Cust_ID order by Order_Date) next_visit_date
		from dbo.e_commerce_data
	) x

--5. Categorise customers using average time gaps. Choose the most fitted labeling model for you.
--For example:
--	o Labeled as churn if the customer hasn't made another purchase in the months since they made their first purchase.
--	o Labeled as regular if the customer has made a purchase every month.
--	Etc.

create view time_gaps as
select * ,
	datediff(month, Order_Date, next_visit_date) time_gap
from (	select Cust_ID, Order_Date,
			lead(Order_Date) over(partition by Cust_ID order by Order_Date) next_visit_date
		from dbo.e_commerce_data
	) x


create view avg_gap as
select avg(avg_time_gap * 1.0) avg_gap
from (
	select Cust_ID, avg(time_gap*1.0) avg_time_gap
	from time_gaps
	group by Cust_ID ) x


select *,
	case 
		when avg_time_gap <= (select * from avg_gap) then 'Regular'
		when avg_time_gap > (select * from avg_gap) then 'Churn'
		when avg_time_gap is NULL then 'Churn'
		end 'Customer_category'
from (
	select Cust_ID, avg(time_gap*1.0) avg_time_gap
	from time_gaps
	group by Cust_ID ) x

--Month-Wise Retention Rate

--Find month-by-month customer retention ratei since the start of the business.
--There are many different variations in the calculation of Retention Rate. But we will try to calculate the month-wise retention rate in this project.
--So, we will be interested in how many of the customers in the previous month could be retained in the next month.
--Proceed step by step by creating “views”. You can use the view you got at the end of the Customer Segmentation section as a source.

--1. Find the number of customers retained month-wise. (You can use time gaps)

create view retention_monthly_wise as
	select distinct *, 
		count(Cust_ID) over(partition by next_visit_date order by Cust_ID, next_visit_date) retention_month_wise
	from time_gaps
	where time_gap = 1

select * from retention_monthly_wise

--2. Calculate the month-wise retention rate.
--	Month-Wise Retention Rate = 1.0 * Number of Customers Retained in The Current Month / Total Number of Customers in the Current Month

create view monthly_retetion_count as
select order_year, order_month, count(Cust_ID) total_retetion 
from (
	select Cust_ID, year(Order_Date) order_year, month(Order_date) order_month,
		case when time_gap = 1 then 'retained' end ret
	from time_gaps ) x
where ret = 'retained'
group by order_year, order_month


create view monthly_total_customer as
select distinct year(Order_Date) order_year, month(Order_Date) order_month,
	count(Cust_ID) over(partition by year(Order_Date), month(Order_Date) order by year(Order_Date), month(Order_Date)) monthly_customer
from dbo.e_commerce_data 
group by YEAR(Order_Date), MONTH(Order_Date), Cust_ID


with t1 as(
	select a.order_year, a.order_month,
		(1.0 * a.total_retetion / b.monthly_customer) rate
	from monthly_retetion_count a , monthly_total_customer b
	where a.order_year = b.order_year and a.order_month = b.order_month 
)
select order_year, order_month,
	cast(rate as decimal(10,2)) retention_rate
from t1
