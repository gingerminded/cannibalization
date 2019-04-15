%let ui=ui2;
/* 
1. У скольких рядов есть промо-САП (внутри того же УИх, за исключением текущего ряда)
2. У скольких рядов цена < цена текущего ряда
3. Появление нового товара с ценой меньше медианы  -- очень мало, см ниже
4. (Максимальное) изменение ранга фактической цены внутри УИх (не учитывая текущий ряд) - макс производная от ранга фактич цены товара
	. высчитываем ранги
	. считаем range(ранг цены) для кажд ряда
	. считаем max (^^^^) для текущ товара по группе УИх (выкидывая текущ товар)
	
Предполагая, что текущий ряд - жертва, коэффициенты при этих indep-ах должны быть отрицательные.
*/ 

proc sql; /*фичи 1,2 собираем из подневных данных*/
create table work.feat as select
t1.product, t1.date as date format=date9., t1.price_fact, sum(t2.promo_sap) as promo_sap_ct , 
sum(ifn(t2.price_fact<t1.price_fact and t2.price_fact ne .,1,0)) as price_lt_victim ,
median(t2.price_fact) as med_price /* медиана по всем, кроме t1.product */
from utkns.denorm_day t1 /*victim*/ , utkns.denorm_day t2 /*all other except victim*/
where t1.product ne t2.product and t1.&ui=t2.&ui and t1.date=t2.date 
group by 1,2,3
;
create table work.feat_week as select /*агрегация до недель*/
t1.product, intnx('week.2',t1.date,0) as date, sum(t1.promo_sap_ct) as promo_sap_ct /* feature 1 */, 
sum(t1.price_lt_victim) as price_lt_victim /* feature 2 */
from work.feat t1
group by 1,2
;
quit;

/*дата первой продажи, для определения новых товаров*/
proc sql;
create table min_sale_dt as
select product, min(date) as min_dt format=date9. from utkns.denorm_day where sales_nr>0.01 group by 1;

create table work.feat_week1 as select /*даты, когда появился товар, размечающий feature 3*/
t1.product, t1.date,t1.price_fact,t1.med_price
from work.feat t1 inner join min_sale_dt t2 on t1.date=t2.min_dt and t1.product=t2.product
where t1.price_fact<t1.med_price 
;
quit;

/*ранги считаем внутри УИх - день*/
proc sort data=utkns.denorm_day out=work.denorm_rank;
by &ui date;
run;
proc rank data=work.denorm_rank out=work.denorm_rank1 ;
by &ui date;
var price_fact;
ranks PriceRank;
run;
/*max(ранг цены)-min(ранг цены), сгруппировано по товар-неделя*/
proc sql;
create table rank_week as  
select product, &ui., intnx('week.2',date,0) as date, range(pricerank) as rank_change
from work.denorm_rank1
group by 1,2,3
;
quit;
proc sql;
create table max_rank_week as select
t1.product, t1.date, max(t2.rank_change) as max_rank_change
from utkns.denorm_week t1 , rank_week t2 
where t1.product ne t2.product and t1.&ui=t2.&ui and t1.date=t2.date 
group by 1,2
;
quit;
/*Джоин с исх данными*/
proc sql;
create table utkns.denorm_week1 as
select t1.*, t3.promo_sap_ct, t3.price_lt_victim, t2.max_rank_change
from (utkns.denorm_week t1 left join work.feat_week t3 on t1.date=t3.date and t1.product=t3.product)
left join max_rank_week t2 on t1.date=t2.date and t1.product=t2.product;
quit;
