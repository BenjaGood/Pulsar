-- PostgreSQL requires new enum values to be committed before they are referenced.
alter type public.food_product_source add value if not exists 'open_nutrition';
