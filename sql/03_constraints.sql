-- Intégrité référentielle sur la couche typée : une table sans clés n'est pas un entrepôt.
ALTER TABLE stg.district ADD PRIMARY KEY (district_id);
ALTER TABLE stg.account  ADD PRIMARY KEY (account_id), ADD FOREIGN KEY (district_id) REFERENCES stg.district;
ALTER TABLE stg.client   ADD PRIMARY KEY (client_id),  ADD FOREIGN KEY (district_id) REFERENCES stg.district;
ALTER TABLE stg.disp     ADD PRIMARY KEY (disp_id),    ADD FOREIGN KEY (client_id) REFERENCES stg.client,
                                                        ADD FOREIGN KEY (account_id) REFERENCES stg.account;
ALTER TABLE stg.loan     ADD PRIMARY KEY (loan_id),    ADD UNIQUE (account_id), ADD FOREIGN KEY (account_id) REFERENCES stg.account,
                         ADD CHECK (status IN ('A','B','C','D')), ADD CHECK (amount_czk > 0);
ALTER TABLE stg.card     ADD PRIMARY KEY (card_id),    ADD FOREIGN KEY (disp_id) REFERENCES stg.disp;
ALTER TABLE stg."order"  ADD PRIMARY KEY (order_id),   ADD FOREIGN KEY (account_id) REFERENCES stg.account;
ALTER TABLE stg.trans    ADD PRIMARY KEY (trans_id),   ADD FOREIGN KEY (account_id) REFERENCES stg.account;
