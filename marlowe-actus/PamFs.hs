Let "tmd_0"
  (Constant 1256169600)
  (Let "nt_0"
     (Constant -1000000000000)
     (Let "ipnr_0"
        (Constant 0)
        (Let "ipac_0"
           (Constant 0)
           (Let "feac_0"
              (Constant 0)
              (Let "fac_0"
                 (Constant 0)
                 (Let "nsc_0"
                    (Constant 1000000000)
                    (Let "isc_0"
                       (Constant 1000000000)
                       (Let "sd_0"
                          (Constant 1224633600)
                          (Let "prnxt_0"
                             (Constant 0)
                             (Let "ipcb_0"
                                (Constant 0)
                                (When [
                                   (Case
                                      (Choice
                                         (ChoiceId "o_rf_CURS_1"
                                            (Role "oracle")) [
                                         (Bound 0 100000000000000)])
                                      (Let "o_rf_CURS_1"
                                         (ChoiceValue
                                            (ChoiceId "o_rf_CURS_1"
                                               (Role "oracle"))
                                            (Constant 0))
                                         (Let "tmd_1"
                                            (UseValue "tmd_0")
                                            (Let "nt_1"
                                               (Scale (1 % 1000000000)
                                                  (MulValue
                                                     (Constant -1)
                                                     (Constant 1000000000000)))
                                               (Let "ipnr_1"
                                                  (Constant 0)
                                                  (Let "ipac_1"
                                                     (Constant 0)
                                                     (Let "feac_1"
                                                        (UseValue "feac_0")
                                                        (Let "fac_1"
                                                           (UseValue "fac_0")
                                                           (Let "nsc_1"
                                                              (UseValue "nsc_0")
                                                              (Let "isc_1"
                                                                 (UseValue "isc_0")
                                                                 (Let "sd_1" SlotIntervalStart
                                                                    (Let "prnxt_1"
                                                                       (UseValue "prnxt_0")
                                                                       (Let "ipcb_1"
                                                                          (UseValue "ipcb_0")
                                                                          (Let "payoff_1"
                                                                             (NegValue
                                                                                (Scale (1 % 1000000000)
                                                                                   (MulValue
                                                                                      (Scale (1 % 1000000000)
                                                                                         (MulValue
                                                                                            (UseValue "o_rf_CURS_1")
                                                                                            (Constant -1)))
                                                                                      (AddValue
                                                                                         (Constant 1000000000000)
                                                                                         (Constant -100000000000)))))
                                                                             (When [
                                                                                (Case
                                                                                   (Deposit
                                                                                      (AccountId 0
                                                                                         (Role "party"))
                                                                                      (Role "party")
                                                                                      (Token "" "")
                                                                                      (UseValue "payoff_1"))
                                                                                   (Pay
                                                                                      (AccountId 0
                                                                                         (Role "party"))
                                                                                      (Party
                                                                                         (Role "counterparty"))
                                                                                      (Token "" "")
                                                                                      (UseValue "payoff_1")
                                                                                      (When [
                                                                                         (Case
                                                                                            (Choice
                                                                                               (ChoiceId "o_rf_CURS_2"
                                                                                                  (Role "oracle")) [
                                                                                               (Bound 0 100000000000000)])
                                                                                            (Let "o_rf_CURS_2"
                                                                                               (ChoiceValue
                                                                                                  (ChoiceId "o_rf_CURS_2"
                                                                                                     (Role "oracle"))
                                                                                                  (Constant 0))
                                                                                               (Let "tmd_2"
                                                                                                  (UseValue "tmd_1")
                                                                                                  (Let "nt_2"
                                                                                                     (Constant 0)
                                                                                                     (Let "ipnr_2"
                                                                                                        (UseValue "ipnr_1")
                                                                                                        (Let "ipac_2"
                                                                                                           (Constant 0)
                                                                                                           (Let "feac_2"
                                                                                                              (Constant 0)
                                                                                                              (Let "fac_2"
                                                                                                                 (UseValue "fac_1")
                                                                                                                 (Let "nsc_2"
                                                                                                                    (UseValue "nsc_1")
                                                                                                                    (Let "isc_2"
                                                                                                                       (UseValue "isc_1")
                                                                                                                       (Let "sd_2" SlotIntervalStart
                                                                                                                          (Let "prnxt_2"
                                                                                                                             (UseValue "prnxt_1")
                                                                                                                             (Let "ipcb_2"
                                                                                                                                (UseValue "ipcb_1")
                                                                                                                                (Let "payoff_2"
                                                                                                                                   (Scale (1 % 1000000000)
                                                                                                                                      (MulValue
                                                                                                                                         (UseValue "o_rf_CURS_2")
                                                                                                                                         (AddValue
                                                                                                                                            (AddValue
                                                                                                                                               (Scale (1 % 1000000000)
                                                                                                                                                  (MulValue
                                                                                                                                                     (UseValue "nsc_2")
                                                                                                                                                     (UseValue "nt_2")))
                                                                                                                                               (Scale (1 % 1000000000)
                                                                                                                                                  (MulValue
                                                                                                                                                     (UseValue "isc_2")
                                                                                                                                                     (UseValue "ipac_2"))))
                                                                                                                                            (UseValue "feac_2"))))
                                                                                                                                   (When [
                                                                                                                                      (Case
                                                                                                                                         (Deposit
                                                                                                                                            (AccountId 0
                                                                                                                                               (Role "counterparty"))
                                                                                                                                            (Role "counterparty")
                                                                                                                                            (Token "" "")
                                                                                                                                            (NegValue
                                                                                                                                               (UseValue "payoff_2")))
                                                                                                                                         (Pay
                                                                                                                                            (AccountId 0
                                                                                                                                               (Role "counterparty"))
                                                                                                                                            (Party
                                                                                                                                               (Role "party"))
                                                                                                                                            (Token "" "")
                                                                                                                                            (NegValue
                                                                                                                                               (UseValue "payoff_2")) Close))] 1256169600 Close)))))))))))))))] 1256169600 Close)))] 1224460800 Close)))))))))))))))] 1224460800 Close)))))))))))