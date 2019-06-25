(program
  (let
    (nonrec)
    (datatypebind
      (datatype
        (tyvardecl Ordering (type))
        
        Ordering_match
        (vardecl EQ Ordering) (vardecl GT Ordering) (vardecl LT Ordering)
      )
    )
    (let
      (nonrec)
      (datatypebind
        (datatype
          (tyvardecl Tuple2 (fun (type) (fun (type) (type))))
          (tyvardecl a (type)) (tyvardecl b (type))
          Tuple2_match
          (vardecl Tuple2 (fun a (fun b [[Tuple2 a] b])))
        )
      )
      (let
        (rec)
        (datatypebind
          (datatype
            (tyvardecl List (fun (type) (type)))
            (tyvardecl a (type))
            Nil_match
            (vardecl Nil [List a])
            (vardecl Cons (fun a (fun [List a] [List a])))
          )
        )
        (let
          (nonrec)
          (datatypebind
            (datatype
              (tyvardecl Bool (type))
              
              Bool_match
              (vardecl True Bool) (vardecl False Bool)
            )
          )
          (let
            (nonrec)
            (datatypebind
              (datatype (tyvardecl Unit (type))  Unit_match (vardecl Unit Unit))
            )
            (let
              (rec)
              (termbind
                (strict)
                (vardecl
                  fFunctorNil_cfmap
                  (all a (type) (all b (type) (fun (fun a b) (fun [List a] [List b]))))
                )
                (abs
                  a
                  (type)
                  (abs
                    b
                    (type)
                    (lam
                      f
                      (fun a b)
                      (lam
                        l
                        [List a]
                        [
                          [
                            [
                              { [ { Nil_match a } l ] (fun Unit [List b]) }
                              (lam thunk Unit { Nil b })
                            ]
                            (lam
                              x
                              a
                              (lam
                                xs
                                [List a]
                                (lam
                                  thunk
                                  Unit
                                  [
                                    [ { Cons b } [ f x ] ]
                                    [ [ { { fFunctorNil_cfmap a } b } f ] xs ]
                                  ]
                                )
                              )
                            )
                          ]
                          Unit
                        ]
                      )
                    )
                  )
                )
              )
              (let
                (rec)
                (termbind
                  (strict)
                  (vardecl
                    foldr
                    (all a (type) (all b (type) (fun (fun a (fun b b)) (fun b (fun [List a] b)))))
                  )
                  (abs
                    a
                    (type)
                    (abs
                      b
                      (type)
                      (lam
                        f
                        (fun a (fun b b))
                        (lam
                          acc
                          b
                          (lam
                            l
                            [List a]
                            [
                              [
                                [
                                  { [ { Nil_match a } l ] (fun Unit b) }
                                  (lam thunk Unit acc)
                                ]
                                (lam
                                  x
                                  a
                                  (lam
                                    xs
                                    [List a]
                                    (lam
                                      thunk
                                      Unit
                                      [
                                        [ f x ]
                                        [ [ [ { { foldr a } b } f ] acc ] xs ]
                                      ]
                                    )
                                  )
                                )
                              ]
                              Unit
                            ]
                          )
                        )
                      )
                    )
                  )
                )
                (let
                  (nonrec)
                  (datatypebind
                    (datatype
                      (tyvardecl These (fun (type) (fun (type) (type))))
                      (tyvardecl a (type)) (tyvardecl b (type))
                      These_match
                      (vardecl That (fun b [[These a] b]))
                      (vardecl These (fun a (fun b [[These a] b])))
                      (vardecl This (fun a [[These a] b]))
                    )
                  )
                  (let
                    (nonrec)
                    (termbind
                      (strict)
                      (vardecl
                        union
                        (all k (type) (all v (type) (all r (type) (fun [(lam a (type) (fun a (fun a Bool))) k] (fun [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) k] v] (fun [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) k] r] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) k] [[These v] r]]))))))
                      )
                      (abs
                        k
                        (type)
                        (abs
                          v
                          (type)
                          (abs
                            r
                            (type)
                            (lam
                              dEq
                              [(lam a (type) (fun a (fun a Bool))) k]
                              (lam
                                ds
                                [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) k] v]
                                (lam
                                  ds1
                                  [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) k] r]
                                  [
                                    [
                                      [
                                        {
                                          { foldr [[Tuple2 k] [[These v] r]] }
                                          [List [[Tuple2 k] [[These v] r]]]
                                        }
                                        { Cons [[Tuple2 k] [[These v] r]] }
                                      ]
                                      [
                                        [
                                          {
                                            { fFunctorNil_cfmap [[Tuple2 k] r] }
                                            [[Tuple2 k] [[These v] r]]
                                          }
                                          (lam
                                            ds2
                                            [[Tuple2 k] r]
                                            [
                                              {
                                                [ { { Tuple2_match k } r } ds2 ]
                                                [[Tuple2 k] [[These v] r]]
                                              }
                                              (lam
                                                c
                                                k
                                                (lam
                                                  b
                                                  r
                                                  [
                                                    [
                                                      {
                                                        { Tuple2 k }
                                                        [[These v] r]
                                                      }
                                                      c
                                                    ]
                                                    [ { { That v } r } b ]
                                                  ]
                                                )
                                              )
                                            ]
                                          )
                                        ]
                                        [
                                          [
                                            [
                                              {
                                                { foldr [[Tuple2 k] r] }
                                                [List [[Tuple2 k] r]]
                                              }
                                              (lam
                                                e
                                                [[Tuple2 k] r]
                                                (lam
                                                  xs
                                                  [List [[Tuple2 k] r]]
                                                  (let
                                                    (nonrec)
                                                    (termbind
                                                      (strict)
                                                      (vardecl
                                                        wild [[Tuple2 k] r]
                                                      )
                                                      e
                                                    )
                                                    [
                                                      {
                                                        [
                                                          {
                                                            { Tuple2_match k } r
                                                          }
                                                          e
                                                        ]
                                                        [List [[Tuple2 k] r]]
                                                      }
                                                      (lam
                                                        c
                                                        k
                                                        (lam
                                                          ds2
                                                          r
                                                          [
                                                            [
                                                              [
                                                                {
                                                                  [
                                                                    Bool_match
                                                                    [
                                                                      [
                                                                        [
                                                                          {
                                                                            {
                                                                              foldr
                                                                              [[Tuple2 k] v]
                                                                            }
                                                                            Bool
                                                                          }
                                                                          (lam
                                                                            a1
                                                                            [[Tuple2 k] v]
                                                                            (lam
                                                                              acc
                                                                              Bool
                                                                              [
                                                                                [
                                                                                  [
                                                                                    {
                                                                                      [
                                                                                        Bool_match
                                                                                        acc
                                                                                      ]
                                                                                      (fun Unit Bool)
                                                                                    }
                                                                                    (lam
                                                                                      thunk
                                                                                      Unit
                                                                                      True
                                                                                    )
                                                                                  ]
                                                                                  (lam
                                                                                    thunk
                                                                                    Unit
                                                                                    [
                                                                                      {
                                                                                        [
                                                                                          {
                                                                                            {
                                                                                              Tuple2_match
                                                                                              k
                                                                                            }
                                                                                            v
                                                                                          }
                                                                                          a1
                                                                                        ]
                                                                                        Bool
                                                                                      }
                                                                                      (lam
                                                                                        c
                                                                                        k
                                                                                        (lam
                                                                                          ds3
                                                                                          v
                                                                                          [
                                                                                            [
                                                                                              dEq
                                                                                              c
                                                                                            ]
                                                                                            c
                                                                                          ]
                                                                                        )
                                                                                      )
                                                                                    ]
                                                                                  )
                                                                                ]
                                                                                Unit
                                                                              ]
                                                                            )
                                                                          )
                                                                        ]
                                                                        False
                                                                      ]
                                                                      ds
                                                                    ]
                                                                  ]
                                                                  (fun Unit [List [[Tuple2 k] r]])
                                                                }
                                                                (lam
                                                                  thunk Unit xs
                                                                )
                                                              ]
                                                              (lam
                                                                thunk
                                                                Unit
                                                                [
                                                                  [
                                                                    {
                                                                      Cons
                                                                      [[Tuple2 k] r]
                                                                    }
                                                                    wild
                                                                  ]
                                                                  xs
                                                                ]
                                                              )
                                                            ]
                                                            Unit
                                                          ]
                                                        )
                                                      )
                                                    ]
                                                  )
                                                )
                                              )
                                            ]
                                            { Nil [[Tuple2 k] r] }
                                          ]
                                          ds1
                                        ]
                                      ]
                                    ]
                                    [
                                      [
                                        {
                                          { fFunctorNil_cfmap [[Tuple2 k] v] }
                                          [[Tuple2 k] [[These v] r]]
                                        }
                                        (lam
                                          ds2
                                          [[Tuple2 k] v]
                                          [
                                            {
                                              [ { { Tuple2_match k } v } ds2 ]
                                              [[Tuple2 k] [[These v] r]]
                                            }
                                            (lam
                                              c
                                              k
                                              (lam
                                                i
                                                v
                                                [
                                                  [
                                                    {
                                                      { Tuple2 k } [[These v] r]
                                                    }
                                                    c
                                                  ]
                                                  (let
                                                    (rec)
                                                    (termbind
                                                      (strict)
                                                      (vardecl
                                                        go
                                                        (fun [List [[Tuple2 k] r]] [[These v] r])
                                                      )
                                                      (lam
                                                        ds3
                                                        [List [[Tuple2 k] r]]
                                                        [
                                                          [
                                                            [
                                                              {
                                                                [
                                                                  {
                                                                    Nil_match
                                                                    [[Tuple2 k] r]
                                                                  }
                                                                  ds3
                                                                ]
                                                                (fun Unit [[These v] r])
                                                              }
                                                              (lam
                                                                thunk
                                                                Unit
                                                                [
                                                                  {
                                                                    { This v } r
                                                                  }
                                                                  i
                                                                ]
                                                              )
                                                            ]
                                                            (lam
                                                              ds4
                                                              [[Tuple2 k] r]
                                                              (lam
                                                                xs
                                                                [List [[Tuple2 k] r]]
                                                                (lam
                                                                  thunk
                                                                  Unit
                                                                  [
                                                                    {
                                                                      [
                                                                        {
                                                                          {
                                                                            Tuple2_match
                                                                            k
                                                                          }
                                                                          r
                                                                        }
                                                                        ds4
                                                                      ]
                                                                      [[These v] r]
                                                                    }
                                                                    (lam
                                                                      c
                                                                      k
                                                                      (lam
                                                                        i1
                                                                        r
                                                                        [
                                                                          [
                                                                            [
                                                                              {
                                                                                [
                                                                                  Bool_match
                                                                                  [
                                                                                    [
                                                                                      dEq
                                                                                      c
                                                                                    ]
                                                                                    c
                                                                                  ]
                                                                                ]
                                                                                (fun Unit [[These v] r])
                                                                              }
                                                                              (lam
                                                                                thunk
                                                                                Unit
                                                                                [
                                                                                  [
                                                                                    {
                                                                                      {
                                                                                        These
                                                                                        v
                                                                                      }
                                                                                      r
                                                                                    }
                                                                                    i
                                                                                  ]
                                                                                  i1
                                                                                ]
                                                                              )
                                                                            ]
                                                                            (lam
                                                                              thunk
                                                                              Unit
                                                                              [
                                                                                go
                                                                                xs
                                                                              ]
                                                                            )
                                                                          ]
                                                                          Unit
                                                                        ]
                                                                      )
                                                                    )
                                                                  ]
                                                                )
                                                              )
                                                            )
                                                          ]
                                                          Unit
                                                        ]
                                                      )
                                                    )
                                                    [ go ds1 ]
                                                  )
                                                ]
                                              )
                                            )
                                          ]
                                        )
                                      ]
                                      ds
                                    ]
                                  ]
                                )
                              )
                            )
                          )
                        )
                      )
                    )
                    (let
                      (rec)
                      (termbind
                        (strict)
                        (vardecl
                          map
                          (all a (type) (all b (type) (fun (fun a b) (fun [List a] [List b]))))
                        )
                        (abs
                          a
                          (type)
                          (abs
                            b
                            (type)
                            (lam
                              f
                              (fun a b)
                              (lam
                                l
                                [List a]
                                [
                                  [
                                    [
                                      {
                                        [ { Nil_match a } l ]
                                        (fun Unit [List b])
                                      }
                                      (lam thunk Unit { Nil b })
                                    ]
                                    (lam
                                      x
                                      a
                                      (lam
                                        xs
                                        [List a]
                                        (lam
                                          thunk
                                          Unit
                                          [
                                            [ { Cons b } [ f x ] ]
                                            [ [ { { map a } b } f ] xs ]
                                          ]
                                        )
                                      )
                                    )
                                  ]
                                  Unit
                                ]
                              )
                            )
                          )
                        )
                      )
                      (let
                        (nonrec)
                        (termbind
                          (strict)
                          (vardecl
                            equalsInteger
                            (fun (con integer) (fun (con integer) Bool))
                          )
                          (lam
                            arg
                            (con integer)
                            (lam
                              arg
                              (con integer)
                              [
                                (lam
                                  b
                                  (all a (type) (fun a (fun a a)))
                                  [ [ { b Bool } True ] False ]
                                )
                                [ [ (builtin equalsInteger) arg ] arg ]
                              ]
                            )
                          )
                        )
                        (let
                          (nonrec)
                          (termbind
                            (strict)
                            (vardecl
                              lessThanEqInteger
                              (fun (con integer) (fun (con integer) Bool))
                            )
                            (lam
                              arg
                              (con integer)
                              (lam
                                arg
                                (con integer)
                                [
                                  (lam
                                    b
                                    (all a (type) (fun a (fun a a)))
                                    [ [ { b Bool } True ] False ]
                                  )
                                  [
                                    [ (builtin lessThanEqualsInteger) arg ] arg
                                  ]
                                ]
                              )
                            )
                          )
                          (let
                            (nonrec)
                            (termbind
                              (strict)
                              (vardecl
                                fOrdInteger_ccompare
                                (fun (con integer) (fun (con integer) Ordering))
                              )
                              (lam
                                x
                                (con integer)
                                (lam
                                  y
                                  (con integer)
                                  [
                                    [
                                      [
                                        {
                                          [
                                            Bool_match [ [ equalsInteger x ] y ]
                                          ]
                                          (fun Unit Ordering)
                                        }
                                        (lam thunk Unit EQ)
                                      ]
                                      (lam
                                        thunk
                                        Unit
                                        [
                                          [
                                            [
                                              {
                                                [
                                                  Bool_match
                                                  [ [ lessThanEqInteger x ] y ]
                                                ]
                                                (fun Unit Ordering)
                                              }
                                              (lam thunk Unit LT)
                                            ]
                                            (lam thunk Unit GT)
                                          ]
                                          Unit
                                        ]
                                      )
                                    ]
                                    Unit
                                  ]
                                )
                              )
                            )
                            (let
                              (nonrec)
                              (termbind
                                (strict)
                                (vardecl
                                  fOrdInteger_cmax
                                  (fun (con integer) (fun (con integer) (con integer)))
                                )
                                (lam
                                  x
                                  (con integer)
                                  (lam
                                    y
                                    (con integer)
                                    [
                                      [
                                        [
                                          {
                                            [
                                              Bool_match
                                              [ [ lessThanEqInteger x ] y ]
                                            ]
                                            (fun Unit (con integer))
                                          }
                                          (lam thunk Unit y)
                                        ]
                                        (lam thunk Unit x)
                                      ]
                                      Unit
                                    ]
                                  )
                                )
                              )
                              (let
                                (nonrec)
                                (termbind
                                  (strict)
                                  (vardecl
                                    fOrdInteger_cmin
                                    (fun (con integer) (fun (con integer) (con integer)))
                                  )
                                  (lam
                                    x
                                    (con integer)
                                    (lam
                                      y
                                      (con integer)
                                      [
                                        [
                                          [
                                            {
                                              [
                                                Bool_match
                                                [ [ lessThanEqInteger x ] y ]
                                              ]
                                              (fun Unit (con integer))
                                            }
                                            (lam thunk Unit x)
                                          ]
                                          (lam thunk Unit y)
                                        ]
                                        Unit
                                      ]
                                    )
                                  )
                                )
                                (let
                                  (nonrec)
                                  (datatypebind
                                    (datatype
                                      (tyvardecl Ord (fun (type) (type)))
                                      (tyvardecl a (type))
                                      Ord_match
                                      (vardecl
                                        CConsOrd
                                        (fun [(lam a (type) (fun a (fun a Bool))) a] (fun (fun a (fun a Ordering)) (fun (fun a (fun a Bool)) (fun (fun a (fun a Bool)) (fun (fun a (fun a Bool)) (fun (fun a (fun a Bool)) (fun (fun a (fun a a)) (fun (fun a (fun a a)) [Ord a]))))))))
                                      )
                                    )
                                  )
                                  (let
                                    (nonrec)
                                    (termbind
                                      (strict)
                                      (vardecl
                                        bad_name
                                        (all a (type) (fun [Ord a] (fun a (fun a Bool))))
                                      )
                                      (abs
                                        a
                                        (type)
                                        (lam
                                          v
                                          [Ord a]
                                          [
                                            {
                                              [ { Ord_match a } v ]
                                              (fun a (fun a Bool))
                                            }
                                            (lam
                                              v
                                              [(lam a (type) (fun a (fun a Bool))) a]
                                              (lam
                                                v
                                                (fun a (fun a Ordering))
                                                (lam
                                                  v
                                                  (fun a (fun a Bool))
                                                  (lam
                                                    v
                                                    (fun a (fun a Bool))
                                                    (lam
                                                      v
                                                      (fun a (fun a Bool))
                                                      (lam
                                                        v
                                                        (fun a (fun a Bool))
                                                        (lam
                                                          v
                                                          (fun a (fun a a))
                                                          (lam
                                                            v
                                                            (fun a (fun a a))
                                                            v
                                                          )
                                                        )
                                                      )
                                                    )
                                                  )
                                                )
                                              )
                                            )
                                          ]
                                        )
                                      )
                                    )
                                    (let
                                      (nonrec)
                                      (termbind
                                        (strict)
                                        (vardecl
                                          bad_name
                                          (all a (type) (fun [Ord a] (fun a (fun a Bool))))
                                        )
                                        (abs
                                          a
                                          (type)
                                          (lam
                                            v
                                            [Ord a]
                                            [
                                              {
                                                [ { Ord_match a } v ]
                                                (fun a (fun a Bool))
                                              }
                                              (lam
                                                v
                                                [(lam a (type) (fun a (fun a Bool))) a]
                                                (lam
                                                  v
                                                  (fun a (fun a Ordering))
                                                  (lam
                                                    v
                                                    (fun a (fun a Bool))
                                                    (lam
                                                      v
                                                      (fun a (fun a Bool))
                                                      (lam
                                                        v
                                                        (fun a (fun a Bool))
                                                        (lam
                                                          v
                                                          (fun a (fun a Bool))
                                                          (lam
                                                            v
                                                            (fun a (fun a a))
                                                            (lam
                                                              v
                                                              (fun a (fun a a))
                                                              v
                                                            )
                                                          )
                                                        )
                                                      )
                                                    )
                                                  )
                                                )
                                              )
                                            ]
                                          )
                                        )
                                      )
                                      (let
                                        (nonrec)
                                        (termbind
                                          (strict)
                                          (vardecl
                                            snd
                                            (all a (type) (all b (type) (fun [[Tuple2 a] b] b)))
                                          )
                                          (abs
                                            a
                                            (type)
                                            (abs
                                              b
                                              (type)
                                              (lam
                                                ds
                                                [[Tuple2 a] b]
                                                [
                                                  {
                                                    [
                                                      { { Tuple2_match a } b }
                                                      ds
                                                    ]
                                                    b
                                                  }
                                                  (lam ds1 a (lam b1 b b1))
                                                ]
                                              )
                                            )
                                          )
                                        )
                                        (let
                                          (nonrec)
                                          (termbind
                                            (strict)
                                            (vardecl
                                              addInteger
                                              (fun (con integer) (fun (con integer) (con integer)))
                                            )
                                            (builtin addInteger)
                                          )
                                          (let
                                            (nonrec)
                                            (termbind
                                              (strict)
                                              (vardecl
                                                emptyByteString (con bytestring)
                                              )
                                              (con #)
                                            )
                                            (let
                                              (nonrec)
                                              (termbind
                                                (strict)
                                                (vardecl
                                                  equalsByteString
                                                  (fun (con bytestring) (fun (con bytestring) Bool))
                                                )
                                                (lam
                                                  arg
                                                  (con bytestring)
                                                  (lam
                                                    arg
                                                    (con bytestring)
                                                    [
                                                      (lam
                                                        b
                                                        (all a (type) (fun a (fun a a)))
                                                        [
                                                          [ { b Bool } True ]
                                                          False
                                                        ]
                                                      )
                                                      [
                                                        [
                                                          (builtin
                                                            equalsByteString
                                                          )
                                                          arg
                                                        ]
                                                        arg
                                                      ]
                                                    ]
                                                  )
                                                )
                                              )
                                              (let
                                                (nonrec)
                                                (termbind
                                                  (strict)
                                                  (vardecl
                                                    error
                                                    (all a (type) (fun Unit a))
                                                  )
                                                  (abs
                                                    e
                                                    (type)
                                                    (lam thunk Unit (error e))
                                                  )
                                                )
                                                (let
                                                  (nonrec)
                                                  (termbind
                                                    (strict)
                                                    (vardecl
                                                      greaterThanEqInteger
                                                      (fun (con integer) (fun (con integer) Bool))
                                                    )
                                                    (lam
                                                      arg
                                                      (con integer)
                                                      (lam
                                                        arg
                                                        (con integer)
                                                        [
                                                          (lam
                                                            b
                                                            (all a (type) (fun a (fun a a)))
                                                            [
                                                              [
                                                                { b Bool } True
                                                              ]
                                                              False
                                                            ]
                                                          )
                                                          [
                                                            [
                                                              (builtin
                                                                greaterThanEqualsInteger
                                                              )
                                                              arg
                                                            ]
                                                            arg
                                                          ]
                                                        ]
                                                      )
                                                    )
                                                  )
                                                  (let
                                                    (nonrec)
                                                    (termbind
                                                      (strict)
                                                      (vardecl
                                                        greaterThanInteger
                                                        (fun (con integer) (fun (con integer) Bool))
                                                      )
                                                      (lam
                                                        arg
                                                        (con integer)
                                                        (lam
                                                          arg
                                                          (con integer)
                                                          [
                                                            (lam
                                                              b
                                                              (all a (type) (fun a (fun a a)))
                                                              [
                                                                [
                                                                  { b Bool }
                                                                  True
                                                                ]
                                                                False
                                                              ]
                                                            )
                                                            [
                                                              [
                                                                (builtin
                                                                  greaterThanInteger
                                                                )
                                                                arg
                                                              ]
                                                              arg
                                                            ]
                                                          ]
                                                        )
                                                      )
                                                    )
                                                    (let
                                                      (nonrec)
                                                      (termbind
                                                        (strict)
                                                        (vardecl
                                                          lessThanInteger
                                                          (fun (con integer) (fun (con integer) Bool))
                                                        )
                                                        (lam
                                                          arg
                                                          (con integer)
                                                          (lam
                                                            arg
                                                            (con integer)
                                                            [
                                                              (lam
                                                                b
                                                                (all a (type) (fun a (fun a a)))
                                                                [
                                                                  [
                                                                    { b Bool }
                                                                    True
                                                                  ]
                                                                  False
                                                                ]
                                                              )
                                                              [
                                                                [
                                                                  (builtin
                                                                    lessThanInteger
                                                                  )
                                                                  arg
                                                                ]
                                                                arg
                                                              ]
                                                            ]
                                                          )
                                                        )
                                                      )
                                                      (let
                                                        (nonrec)
                                                        (termbind
                                                          (strict)
                                                          (vardecl
                                                            multiplyInteger
                                                            (fun (con integer) (fun (con integer) (con integer)))
                                                          )
                                                          (builtin
                                                            multiplyInteger
                                                          )
                                                        )
                                                        (let
                                                          (nonrec)
                                                          (termbind
                                                            (strict)
                                                            (vardecl
                                                              subtractInteger
                                                              (fun (con integer) (fun (con integer) (con integer)))
                                                            )
                                                            (builtin
                                                              subtractInteger
                                                            )
                                                          )
                                                          (let
                                                            (nonrec)
                                                            (datatypebind
                                                              (datatype
                                                                (tyvardecl
                                                                  Future (type)
                                                                )
                                                                
                                                                Future_match
                                                                (vardecl
                                                                  Future
                                                                  (fun (con integer) (fun (con integer) (fun (con integer) (fun (con integer) (fun (con bytestring) (fun (con integer) Future))))))
                                                                )
                                                              )
                                                            )
                                                            (let
                                                              (nonrec)
                                                              (datatypebind
                                                                (datatype
                                                                  (tyvardecl
                                                                    FutureData
                                                                    (type)
                                                                  )
                                                                  
                                                                  FutureData_match
                                                                  (vardecl
                                                                    FutureData
                                                                    (fun (con bytestring) (fun (con bytestring) (fun (con integer) (fun (con integer) FutureData))))
                                                                  )
                                                                )
                                                              )
                                                              (let
                                                                (nonrec)
                                                                (datatypebind
                                                                  (datatype
                                                                    (tyvardecl
                                                                      OracleValue
                                                                      (fun (type) (type))
                                                                    )
                                                                    (tyvardecl
                                                                      a (type)
                                                                    )
                                                                    OracleValue_match
                                                                    (vardecl
                                                                      OracleValue
                                                                      (fun (con bytestring) (fun (con integer) (fun a [OracleValue a])))
                                                                    )
                                                                  )
                                                                )
                                                                (let
                                                                  (nonrec)
                                                                  (datatypebind
                                                                    (datatype
                                                                      (tyvardecl
                                                                        FutureRedeemer
                                                                        (type)
                                                                      )
                                                                      
                                                                      FutureRedeemer_match
                                                                      (vardecl
                                                                        AdjustMargin
                                                                        FutureRedeemer
                                                                      )
                                                                      (vardecl
                                                                        Settle
                                                                        (fun [OracleValue (con integer)] FutureRedeemer)
                                                                      )
                                                                    )
                                                                  )
                                                                  (let
                                                                    (nonrec)
                                                                    (datatypebind
                                                                      (datatype
                                                                        (tyvardecl
                                                                          Maybe
                                                                          (fun (type) (type))
                                                                        )
                                                                        (tyvardecl
                                                                          a
                                                                          (type)
                                                                        )
                                                                        Maybe_match
                                                                        (vardecl
                                                                          Just
                                                                          (fun a [Maybe a])
                                                                        )
                                                                        (vardecl
                                                                          Nothing
                                                                          [Maybe a]
                                                                        )
                                                                      )
                                                                    )
                                                                    (let
                                                                      (nonrec)
                                                                      (datatypebind
                                                                        (datatype
                                                                          (tyvardecl
                                                                            Interval
                                                                            (fun (type) (type))
                                                                          )
                                                                          (tyvardecl
                                                                            a
                                                                            (type)
                                                                          )
                                                                          Interval_match
                                                                          (vardecl
                                                                            Interval
                                                                            (fun [Maybe a] (fun [Maybe a] [Interval a]))
                                                                          )
                                                                        )
                                                                      )
                                                                      (let
                                                                        (nonrec)
                                                                        (termbind
                                                                          (strict
                                                                          )
                                                                          (vardecl
                                                                            wmember
                                                                            (all a (type) (fun [Ord a] (fun a (fun [Maybe a] (fun [Maybe a] Bool)))))
                                                                          )
                                                                          (abs
                                                                            a
                                                                            (type)
                                                                            (lam
                                                                              w
                                                                              [Ord a]
                                                                              (lam
                                                                                w5
                                                                                a
                                                                                (lam
                                                                                  ww
                                                                                  [Maybe a]
                                                                                  (lam
                                                                                    ww1
                                                                                    [Maybe a]
                                                                                    [
                                                                                      [
                                                                                        [
                                                                                          {
                                                                                            [
                                                                                              {
                                                                                                Maybe_match
                                                                                                a
                                                                                              }
                                                                                              ww
                                                                                            ]
                                                                                            (fun Unit Bool)
                                                                                          }
                                                                                          (lam
                                                                                            f
                                                                                            a
                                                                                            (lam
                                                                                              thunk
                                                                                              Unit
                                                                                              [
                                                                                                [
                                                                                                  [
                                                                                                    {
                                                                                                      [
                                                                                                        Bool_match
                                                                                                        [
                                                                                                          [
                                                                                                            [
                                                                                                              {
                                                                                                                bad_name
                                                                                                                a
                                                                                                              }
                                                                                                              w
                                                                                                            ]
                                                                                                            f
                                                                                                          ]
                                                                                                          w5
                                                                                                        ]
                                                                                                      ]
                                                                                                      (fun Unit Bool)
                                                                                                    }
                                                                                                    (lam
                                                                                                      thunk
                                                                                                      Unit
                                                                                                      [
                                                                                                        [
                                                                                                          [
                                                                                                            {
                                                                                                              [
                                                                                                                {
                                                                                                                  Maybe_match
                                                                                                                  a
                                                                                                                }
                                                                                                                ww1
                                                                                                              ]
                                                                                                              (fun Unit Bool)
                                                                                                            }
                                                                                                            (lam
                                                                                                              t
                                                                                                              a
                                                                                                              (lam
                                                                                                                thunk
                                                                                                                Unit
                                                                                                                [
                                                                                                                  [
                                                                                                                    [
                                                                                                                      {
                                                                                                                        bad_name
                                                                                                                        a
                                                                                                                      }
                                                                                                                      w
                                                                                                                    ]
                                                                                                                    t
                                                                                                                  ]
                                                                                                                  w5
                                                                                                                ]
                                                                                                              )
                                                                                                            )
                                                                                                          ]
                                                                                                          (lam
                                                                                                            thunk
                                                                                                            Unit
                                                                                                            True
                                                                                                          )
                                                                                                        ]
                                                                                                        Unit
                                                                                                      ]
                                                                                                    )
                                                                                                  ]
                                                                                                  (lam
                                                                                                    thunk
                                                                                                    Unit
                                                                                                    False
                                                                                                  )
                                                                                                ]
                                                                                                Unit
                                                                                              ]
                                                                                            )
                                                                                          )
                                                                                        ]
                                                                                        (lam
                                                                                          thunk
                                                                                          Unit
                                                                                          [
                                                                                            [
                                                                                              [
                                                                                                {
                                                                                                  [
                                                                                                    {
                                                                                                      Maybe_match
                                                                                                      a
                                                                                                    }
                                                                                                    ww1
                                                                                                  ]
                                                                                                  (fun Unit Bool)
                                                                                                }
                                                                                                (lam
                                                                                                  t
                                                                                                  a
                                                                                                  (lam
                                                                                                    thunk
                                                                                                    Unit
                                                                                                    [
                                                                                                      [
                                                                                                        [
                                                                                                          {
                                                                                                            bad_name
                                                                                                            a
                                                                                                          }
                                                                                                          w
                                                                                                        ]
                                                                                                        t
                                                                                                      ]
                                                                                                      w5
                                                                                                    ]
                                                                                                  )
                                                                                                )
                                                                                              ]
                                                                                              (lam
                                                                                                thunk
                                                                                                Unit
                                                                                                True
                                                                                              )
                                                                                            ]
                                                                                            Unit
                                                                                          ]
                                                                                        )
                                                                                      ]
                                                                                      Unit
                                                                                    ]
                                                                                  )
                                                                                )
                                                                              )
                                                                            )
                                                                          )
                                                                        )
                                                                        (let
                                                                          (nonrec
                                                                          )
                                                                          (termbind
                                                                            (strict
                                                                            )
                                                                            (vardecl
                                                                              member
                                                                              (all a (type) (fun [Ord a] (fun a (fun [Interval a] Bool))))
                                                                            )
                                                                            (abs
                                                                              a
                                                                              (type)
                                                                              (lam
                                                                                w
                                                                                [Ord a]
                                                                                (lam
                                                                                  w5
                                                                                  a
                                                                                  (lam
                                                                                    w6
                                                                                    [Interval a]
                                                                                    [
                                                                                      {
                                                                                        [
                                                                                          {
                                                                                            Interval_match
                                                                                            a
                                                                                          }
                                                                                          w6
                                                                                        ]
                                                                                        Bool
                                                                                      }
                                                                                      (lam
                                                                                        ww1
                                                                                        [Maybe a]
                                                                                        (lam
                                                                                          ww2
                                                                                          [Maybe a]
                                                                                          [
                                                                                            [
                                                                                              [
                                                                                                [
                                                                                                  {
                                                                                                    wmember
                                                                                                    a
                                                                                                  }
                                                                                                  w
                                                                                                ]
                                                                                                w5
                                                                                              ]
                                                                                              ww1
                                                                                            ]
                                                                                            ww2
                                                                                          ]
                                                                                        )
                                                                                      )
                                                                                    ]
                                                                                  )
                                                                                )
                                                                              )
                                                                            )
                                                                          )
                                                                          (let
                                                                            (nonrec
                                                                            )
                                                                            (termbind
                                                                              (nonstrict
                                                                              )
                                                                              (vardecl
                                                                                fOrdSlot0
                                                                                [Ord (con integer)]
                                                                              )
                                                                              [
                                                                                [
                                                                                  [
                                                                                    [
                                                                                      [
                                                                                        [
                                                                                          [
                                                                                            [
                                                                                              {
                                                                                                CConsOrd
                                                                                                (con integer)
                                                                                              }
                                                                                              equalsInteger
                                                                                            ]
                                                                                            fOrdInteger_ccompare
                                                                                          ]
                                                                                          lessThanInteger
                                                                                        ]
                                                                                        lessThanEqInteger
                                                                                      ]
                                                                                      greaterThanInteger
                                                                                    ]
                                                                                    greaterThanEqInteger
                                                                                  ]
                                                                                  fOrdInteger_cmax
                                                                                ]
                                                                                fOrdInteger_cmin
                                                                              ]
                                                                            )
                                                                            (let
                                                                              (nonrec
                                                                              )
                                                                              (datatypebind
                                                                                (datatype
                                                                                  (tyvardecl
                                                                                    PendingTxOutRef
                                                                                    (type)
                                                                                  )
                                                                                  
                                                                                  PendingTxOutRef_match
                                                                                  (vardecl
                                                                                    PendingTxOutRef
                                                                                    (fun (con bytestring) (fun (con integer) PendingTxOutRef))
                                                                                  )
                                                                                )
                                                                              )
                                                                              (let
                                                                                (nonrec
                                                                                )
                                                                                (datatypebind
                                                                                  (datatype
                                                                                    (tyvardecl
                                                                                      PendingTxIn
                                                                                      (type)
                                                                                    )
                                                                                    
                                                                                    PendingTxIn_match
                                                                                    (vardecl
                                                                                      PendingTxIn
                                                                                      (fun PendingTxOutRef (fun [Maybe [[Tuple2 (con bytestring)] (con bytestring)]] (fun [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]] PendingTxIn)))
                                                                                    )
                                                                                  )
                                                                                )
                                                                                (let
                                                                                  (nonrec
                                                                                  )
                                                                                  (datatypebind
                                                                                    (datatype
                                                                                      (tyvardecl
                                                                                        PendingTxOutType
                                                                                        (type)
                                                                                      )
                                                                                      
                                                                                      PendingTxOutType_match
                                                                                      (vardecl
                                                                                        DataTxOut
                                                                                        PendingTxOutType
                                                                                      )
                                                                                      (vardecl
                                                                                        PubKeyTxOut
                                                                                        (fun (con bytestring) PendingTxOutType)
                                                                                      )
                                                                                    )
                                                                                  )
                                                                                  (let
                                                                                    (nonrec
                                                                                    )
                                                                                    (datatypebind
                                                                                      (datatype
                                                                                        (tyvardecl
                                                                                          PendingTxOut
                                                                                          (type)
                                                                                        )
                                                                                        
                                                                                        PendingTxOut_match
                                                                                        (vardecl
                                                                                          PendingTxOut
                                                                                          (fun [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]] (fun [Maybe [[Tuple2 (con bytestring)] (con bytestring)]] (fun PendingTxOutType PendingTxOut)))
                                                                                        )
                                                                                      )
                                                                                    )
                                                                                    (let
                                                                                      (nonrec
                                                                                      )
                                                                                      (datatypebind
                                                                                        (datatype
                                                                                          (tyvardecl
                                                                                            PendingTx
                                                                                            (type)
                                                                                          )
                                                                                          
                                                                                          PendingTx_match
                                                                                          (vardecl
                                                                                            PendingTx
                                                                                            (fun [List PendingTxIn] (fun [List PendingTxOut] (fun (con integer) (fun [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]] (fun PendingTxIn (fun [Interval (con integer)] (fun [List [[Tuple2 (con bytestring)] (con bytestring)]] (fun (con bytestring) PendingTx))))))))
                                                                                          )
                                                                                        )
                                                                                      )
                                                                                      (let
                                                                                        (nonrec
                                                                                        )
                                                                                        (termbind
                                                                                          (strict
                                                                                          )
                                                                                          (vardecl
                                                                                            wscriptOutputsAt
                                                                                            (fun (con bytestring) (fun [List PendingTxOut] [List [[Tuple2 (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]]]))
                                                                                          )
                                                                                          (lam
                                                                                            w
                                                                                            (con bytestring)
                                                                                            (lam
                                                                                              ww
                                                                                              [List PendingTxOut]
                                                                                              [
                                                                                                [
                                                                                                  [
                                                                                                    {
                                                                                                      {
                                                                                                        foldr
                                                                                                        PendingTxOut
                                                                                                      }
                                                                                                      [List [[Tuple2 (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]]]
                                                                                                    }
                                                                                                    (lam
                                                                                                      e
                                                                                                      PendingTxOut
                                                                                                      (lam
                                                                                                        xs
                                                                                                        [List [[Tuple2 (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]]]
                                                                                                        [
                                                                                                          {
                                                                                                            [
                                                                                                              PendingTxOut_match
                                                                                                              e
                                                                                                            ]
                                                                                                            [List [[Tuple2 (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]]]
                                                                                                          }
                                                                                                          (lam
                                                                                                            ds
                                                                                                            [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]
                                                                                                            (lam
                                                                                                              ds1
                                                                                                              [Maybe [[Tuple2 (con bytestring)] (con bytestring)]]
                                                                                                              (lam
                                                                                                                ds2
                                                                                                                PendingTxOutType
                                                                                                                [
                                                                                                                  [
                                                                                                                    [
                                                                                                                      {
                                                                                                                        [
                                                                                                                          {
                                                                                                                            Maybe_match
                                                                                                                            [[Tuple2 (con bytestring)] (con bytestring)]
                                                                                                                          }
                                                                                                                          ds1
                                                                                                                        ]
                                                                                                                        (fun Unit [List [[Tuple2 (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]]])
                                                                                                                      }
                                                                                                                      (lam
                                                                                                                        ds3
                                                                                                                        [[Tuple2 (con bytestring)] (con bytestring)]
                                                                                                                        (lam
                                                                                                                          thunk
                                                                                                                          Unit
                                                                                                                          [
                                                                                                                            {
                                                                                                                              [
                                                                                                                                {
                                                                                                                                  {
                                                                                                                                    Tuple2_match
                                                                                                                                    (con bytestring)
                                                                                                                                  }
                                                                                                                                  (con bytestring)
                                                                                                                                }
                                                                                                                                ds3
                                                                                                                              ]
                                                                                                                              [List [[Tuple2 (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]]]
                                                                                                                            }
                                                                                                                            (lam
                                                                                                                              h
                                                                                                                              (con bytestring)
                                                                                                                              (lam
                                                                                                                                ds4
                                                                                                                                (con bytestring)
                                                                                                                                [
                                                                                                                                  [
                                                                                                                                    [
                                                                                                                                      {
                                                                                                                                        [
                                                                                                                                          Bool_match
                                                                                                                                          [
                                                                                                                                            [
                                                                                                                                              equalsByteString
                                                                                                                                              w
                                                                                                                                            ]
                                                                                                                                            h
                                                                                                                                          ]
                                                                                                                                        ]
                                                                                                                                        (fun Unit [List [[Tuple2 (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]]])
                                                                                                                                      }
                                                                                                                                      (lam
                                                                                                                                        thunk
                                                                                                                                        Unit
                                                                                                                                        [
                                                                                                                                          [
                                                                                                                                            {
                                                                                                                                              Cons
                                                                                                                                              [[Tuple2 (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]]
                                                                                                                                            }
                                                                                                                                            [
                                                                                                                                              [
                                                                                                                                                {
                                                                                                                                                  {
                                                                                                                                                    Tuple2
                                                                                                                                                    (con bytestring)
                                                                                                                                                  }
                                                                                                                                                  [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]
                                                                                                                                                }
                                                                                                                                                ds4
                                                                                                                                              ]
                                                                                                                                              ds
                                                                                                                                            ]
                                                                                                                                          ]
                                                                                                                                          xs
                                                                                                                                        ]
                                                                                                                                      )
                                                                                                                                    ]
                                                                                                                                    (lam
                                                                                                                                      thunk
                                                                                                                                      Unit
                                                                                                                                      xs
                                                                                                                                    )
                                                                                                                                  ]
                                                                                                                                  Unit
                                                                                                                                ]
                                                                                                                              )
                                                                                                                            )
                                                                                                                          ]
                                                                                                                        )
                                                                                                                      )
                                                                                                                    ]
                                                                                                                    (lam
                                                                                                                      thunk
                                                                                                                      Unit
                                                                                                                      xs
                                                                                                                    )
                                                                                                                  ]
                                                                                                                  Unit
                                                                                                                ]
                                                                                                              )
                                                                                                            )
                                                                                                          )
                                                                                                        ]
                                                                                                      )
                                                                                                    )
                                                                                                  ]
                                                                                                  {
                                                                                                    Nil
                                                                                                    [[Tuple2 (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]]
                                                                                                  }
                                                                                                ]
                                                                                                ww
                                                                                              ]
                                                                                            )
                                                                                          )
                                                                                        )
                                                                                        (let
                                                                                          (nonrec
                                                                                          )
                                                                                          (termbind
                                                                                            (strict
                                                                                            )
                                                                                            (vardecl
                                                                                              unionVal
                                                                                              (fun [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]] (fun [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[These (con integer)] (con integer)]]]))
                                                                                            )
                                                                                            (lam
                                                                                              ds
                                                                                              [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]
                                                                                              (lam
                                                                                                ds1
                                                                                                [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]
                                                                                                (let
                                                                                                  (rec
                                                                                                  )
                                                                                                  (termbind
                                                                                                    (strict
                                                                                                    )
                                                                                                    (vardecl
                                                                                                      go7
                                                                                                      (fun [List [[Tuple2 (con bytestring)] [[These [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]]] [List [[Tuple2 (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[These (con integer)] (con integer)]]]])
                                                                                                    )
                                                                                                    (lam
                                                                                                      ds2
                                                                                                      [List [[Tuple2 (con bytestring)] [[These [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]]]
                                                                                                      [
                                                                                                        [
                                                                                                          [
                                                                                                            {
                                                                                                              [
                                                                                                                {
                                                                                                                  Nil_match
                                                                                                                  [[Tuple2 (con bytestring)] [[These [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]]
                                                                                                                }
                                                                                                                ds2
                                                                                                              ]
                                                                                                              (fun Unit [List [[Tuple2 (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[These (con integer)] (con integer)]]]])
                                                                                                            }
                                                                                                            (lam
                                                                                                              thunk
                                                                                                              Unit
                                                                                                              {
                                                                                                                Nil
                                                                                                                [[Tuple2 (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[These (con integer)] (con integer)]]]
                                                                                                              }
                                                                                                            )
                                                                                                          ]
                                                                                                          (lam
                                                                                                            ds3
                                                                                                            [[Tuple2 (con bytestring)] [[These [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]]
                                                                                                            (lam
                                                                                                              xs
                                                                                                              [List [[Tuple2 (con bytestring)] [[These [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]]]
                                                                                                              (lam
                                                                                                                thunk
                                                                                                                Unit
                                                                                                                [
                                                                                                                  {
                                                                                                                    [
                                                                                                                      {
                                                                                                                        {
                                                                                                                          Tuple2_match
                                                                                                                          (con bytestring)
                                                                                                                        }
                                                                                                                        [[These [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]
                                                                                                                      }
                                                                                                                      ds3
                                                                                                                    ]
                                                                                                                    [List [[Tuple2 (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[These (con integer)] (con integer)]]]]
                                                                                                                  }
                                                                                                                  (lam
                                                                                                                    c
                                                                                                                    (con bytestring)
                                                                                                                    (lam
                                                                                                                      i
                                                                                                                      [[These [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]
                                                                                                                      [
                                                                                                                        [
                                                                                                                          {
                                                                                                                            Cons
                                                                                                                            [[Tuple2 (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[These (con integer)] (con integer)]]]
                                                                                                                          }
                                                                                                                          [
                                                                                                                            [
                                                                                                                              {
                                                                                                                                {
                                                                                                                                  Tuple2
                                                                                                                                  (con bytestring)
                                                                                                                                }
                                                                                                                                [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[These (con integer)] (con integer)]]
                                                                                                                              }
                                                                                                                              c
                                                                                                                            ]
                                                                                                                            [
                                                                                                                              [
                                                                                                                                [
                                                                                                                                  {
                                                                                                                                    [
                                                                                                                                      {
                                                                                                                                        {
                                                                                                                                          These_match
                                                                                                                                          [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]
                                                                                                                                        }
                                                                                                                                        [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]
                                                                                                                                      }
                                                                                                                                      i
                                                                                                                                    ]
                                                                                                                                    [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[These (con integer)] (con integer)]]
                                                                                                                                  }
                                                                                                                                  (lam
                                                                                                                                    b
                                                                                                                                    [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]
                                                                                                                                    (let
                                                                                                                                      (rec
                                                                                                                                      )
                                                                                                                                      (termbind
                                                                                                                                        (strict
                                                                                                                                        )
                                                                                                                                        (vardecl
                                                                                                                                          go8
                                                                                                                                          (fun [List [[Tuple2 (con bytestring)] (con integer)]] [List [[Tuple2 (con bytestring)] [[These (con integer)] (con integer)]]])
                                                                                                                                        )
                                                                                                                                        (lam
                                                                                                                                          ds4
                                                                                                                                          [List [[Tuple2 (con bytestring)] (con integer)]]
                                                                                                                                          [
                                                                                                                                            [
                                                                                                                                              [
                                                                                                                                                {
                                                                                                                                                  [
                                                                                                                                                    {
                                                                                                                                                      Nil_match
                                                                                                                                                      [[Tuple2 (con bytestring)] (con integer)]
                                                                                                                                                    }
                                                                                                                                                    ds4
                                                                                                                                                  ]
                                                                                                                                                  (fun Unit [List [[Tuple2 (con bytestring)] [[These (con integer)] (con integer)]]])
                                                                                                                                                }
                                                                                                                                                (lam
                                                                                                                                                  thunk
                                                                                                                                                  Unit
                                                                                                                                                  {
                                                                                                                                                    Nil
                                                                                                                                                    [[Tuple2 (con bytestring)] [[These (con integer)] (con integer)]]
                                                                                                                                                  }
                                                                                                                                                )
                                                                                                                                              ]
                                                                                                                                              (lam
                                                                                                                                                ds5
                                                                                                                                                [[Tuple2 (con bytestring)] (con integer)]
                                                                                                                                                (lam
                                                                                                                                                  xs1
                                                                                                                                                  [List [[Tuple2 (con bytestring)] (con integer)]]
                                                                                                                                                  (lam
                                                                                                                                                    thunk
                                                                                                                                                    Unit
                                                                                                                                                    [
                                                                                                                                                      {
                                                                                                                                                        [
                                                                                                                                                          {
                                                                                                                                                            {
                                                                                                                                                              Tuple2_match
                                                                                                                                                              (con bytestring)
                                                                                                                                                            }
                                                                                                                                                            (con integer)
                                                                                                                                                          }
                                                                                                                                                          ds5
                                                                                                                                                        ]
                                                                                                                                                        [List [[Tuple2 (con bytestring)] [[These (con integer)] (con integer)]]]
                                                                                                                                                      }
                                                                                                                                                      (lam
                                                                                                                                                        c1
                                                                                                                                                        (con bytestring)
                                                                                                                                                        (lam
                                                                                                                                                          i1
                                                                                                                                                          (con integer)
                                                                                                                                                          [
                                                                                                                                                            [
                                                                                                                                                              {
                                                                                                                                                                Cons
                                                                                                                                                                [[Tuple2 (con bytestring)] [[These (con integer)] (con integer)]]
                                                                                                                                                              }
                                                                                                                                                              [
                                                                                                                                                                [
                                                                                                                                                                  {
                                                                                                                                                                    {
                                                                                                                                                                      Tuple2
                                                                                                                                                                      (con bytestring)
                                                                                                                                                                    }
                                                                                                                                                                    [[These (con integer)] (con integer)]
                                                                                                                                                                  }
                                                                                                                                                                  c1
                                                                                                                                                                ]
                                                                                                                                                                [
                                                                                                                                                                  {
                                                                                                                                                                    {
                                                                                                                                                                      That
                                                                                                                                                                      (con integer)
                                                                                                                                                                    }
                                                                                                                                                                    (con integer)
                                                                                                                                                                  }
                                                                                                                                                                  i1
                                                                                                                                                                ]
                                                                                                                                                              ]
                                                                                                                                                            ]
                                                                                                                                                            [
                                                                                                                                                              go8
                                                                                                                                                              xs1
                                                                                                                                                            ]
                                                                                                                                                          ]
                                                                                                                                                        )
                                                                                                                                                      )
                                                                                                                                                    ]
                                                                                                                                                  )
                                                                                                                                                )
                                                                                                                                              )
                                                                                                                                            ]
                                                                                                                                            Unit
                                                                                                                                          ]
                                                                                                                                        )
                                                                                                                                      )
                                                                                                                                      [
                                                                                                                                        go8
                                                                                                                                        b
                                                                                                                                      ]
                                                                                                                                    )
                                                                                                                                  )
                                                                                                                                ]
                                                                                                                                (lam
                                                                                                                                  a
                                                                                                                                  [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]
                                                                                                                                  (lam
                                                                                                                                    b
                                                                                                                                    [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]
                                                                                                                                    [
                                                                                                                                      [
                                                                                                                                        [
                                                                                                                                          {
                                                                                                                                            {
                                                                                                                                              {
                                                                                                                                                union
                                                                                                                                                (con bytestring)
                                                                                                                                              }
                                                                                                                                              (con integer)
                                                                                                                                            }
                                                                                                                                            (con integer)
                                                                                                                                          }
                                                                                                                                          equalsByteString
                                                                                                                                        ]
                                                                                                                                        a
                                                                                                                                      ]
                                                                                                                                      b
                                                                                                                                    ]
                                                                                                                                  )
                                                                                                                                )
                                                                                                                              ]
                                                                                                                              (lam
                                                                                                                                a
                                                                                                                                [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]
                                                                                                                                (let
                                                                                                                                  (rec
                                                                                                                                  )
                                                                                                                                  (termbind
                                                                                                                                    (strict
                                                                                                                                    )
                                                                                                                                    (vardecl
                                                                                                                                      go8
                                                                                                                                      (fun [List [[Tuple2 (con bytestring)] (con integer)]] [List [[Tuple2 (con bytestring)] [[These (con integer)] (con integer)]]])
                                                                                                                                    )
                                                                                                                                    (lam
                                                                                                                                      ds4
                                                                                                                                      [List [[Tuple2 (con bytestring)] (con integer)]]
                                                                                                                                      [
                                                                                                                                        [
                                                                                                                                          [
                                                                                                                                            {
                                                                                                                                              [
                                                                                                                                                {
                                                                                                                                                  Nil_match
                                                                                                                                                  [[Tuple2 (con bytestring)] (con integer)]
                                                                                                                                                }
                                                                                                                                                ds4
                                                                                                                                              ]
                                                                                                                                              (fun Unit [List [[Tuple2 (con bytestring)] [[These (con integer)] (con integer)]]])
                                                                                                                                            }
                                                                                                                                            (lam
                                                                                                                                              thunk
                                                                                                                                              Unit
                                                                                                                                              {
                                                                                                                                                Nil
                                                                                                                                                [[Tuple2 (con bytestring)] [[These (con integer)] (con integer)]]
                                                                                                                                              }
                                                                                                                                            )
                                                                                                                                          ]
                                                                                                                                          (lam
                                                                                                                                            ds5
                                                                                                                                            [[Tuple2 (con bytestring)] (con integer)]
                                                                                                                                            (lam
                                                                                                                                              xs1
                                                                                                                                              [List [[Tuple2 (con bytestring)] (con integer)]]
                                                                                                                                              (lam
                                                                                                                                                thunk
                                                                                                                                                Unit
                                                                                                                                                [
                                                                                                                                                  {
                                                                                                                                                    [
                                                                                                                                                      {
                                                                                                                                                        {
                                                                                                                                                          Tuple2_match
                                                                                                                                                          (con bytestring)
                                                                                                                                                        }
                                                                                                                                                        (con integer)
                                                                                                                                                      }
                                                                                                                                                      ds5
                                                                                                                                                    ]
                                                                                                                                                    [List [[Tuple2 (con bytestring)] [[These (con integer)] (con integer)]]]
                                                                                                                                                  }
                                                                                                                                                  (lam
                                                                                                                                                    c1
                                                                                                                                                    (con bytestring)
                                                                                                                                                    (lam
                                                                                                                                                      i1
                                                                                                                                                      (con integer)
                                                                                                                                                      [
                                                                                                                                                        [
                                                                                                                                                          {
                                                                                                                                                            Cons
                                                                                                                                                            [[Tuple2 (con bytestring)] [[These (con integer)] (con integer)]]
                                                                                                                                                          }
                                                                                                                                                          [
                                                                                                                                                            [
                                                                                                                                                              {
                                                                                                                                                                {
                                                                                                                                                                  Tuple2
                                                                                                                                                                  (con bytestring)
                                                                                                                                                                }
                                                                                                                                                                [[These (con integer)] (con integer)]
                                                                                                                                                              }
                                                                                                                                                              c1
                                                                                                                                                            ]
                                                                                                                                                            [
                                                                                                                                                              {
                                                                                                                                                                {
                                                                                                                                                                  This
                                                                                                                                                                  (con integer)
                                                                                                                                                                }
                                                                                                                                                                (con integer)
                                                                                                                                                              }
                                                                                                                                                              i1
                                                                                                                                                            ]
                                                                                                                                                          ]
                                                                                                                                                        ]
                                                                                                                                                        [
                                                                                                                                                          go8
                                                                                                                                                          xs1
                                                                                                                                                        ]
                                                                                                                                                      ]
                                                                                                                                                    )
                                                                                                                                                  )
                                                                                                                                                ]
                                                                                                                                              )
                                                                                                                                            )
                                                                                                                                          )
                                                                                                                                        ]
                                                                                                                                        Unit
                                                                                                                                      ]
                                                                                                                                    )
                                                                                                                                  )
                                                                                                                                  [
                                                                                                                                    go8
                                                                                                                                    a
                                                                                                                                  ]
                                                                                                                                )
                                                                                                                              )
                                                                                                                            ]
                                                                                                                          ]
                                                                                                                        ]
                                                                                                                        [
                                                                                                                          go7
                                                                                                                          xs
                                                                                                                        ]
                                                                                                                      ]
                                                                                                                    )
                                                                                                                  )
                                                                                                                ]
                                                                                                              )
                                                                                                            )
                                                                                                          )
                                                                                                        ]
                                                                                                        Unit
                                                                                                      ]
                                                                                                    )
                                                                                                  )
                                                                                                  [
                                                                                                    go7
                                                                                                    [
                                                                                                      [
                                                                                                        [
                                                                                                          {
                                                                                                            {
                                                                                                              {
                                                                                                                union
                                                                                                                (con bytestring)
                                                                                                              }
                                                                                                              [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]
                                                                                                            }
                                                                                                            [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]
                                                                                                          }
                                                                                                          equalsByteString
                                                                                                        ]
                                                                                                        ds
                                                                                                      ]
                                                                                                      ds1
                                                                                                    ]
                                                                                                  ]
                                                                                                )
                                                                                              )
                                                                                            )
                                                                                          )
                                                                                          (let
                                                                                            (nonrec
                                                                                            )
                                                                                            (termbind
                                                                                              (strict
                                                                                              )
                                                                                              (vardecl
                                                                                                unionWith
                                                                                                (fun (fun (con integer) (fun (con integer) (con integer))) (fun [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]] (fun [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]])))
                                                                                              )
                                                                                              (lam
                                                                                                f
                                                                                                (fun (con integer) (fun (con integer) (con integer)))
                                                                                                (lam
                                                                                                  ls
                                                                                                  [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]
                                                                                                  (lam
                                                                                                    rs
                                                                                                    [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]
                                                                                                    (let
                                                                                                      (rec
                                                                                                      )
                                                                                                      (termbind
                                                                                                        (strict
                                                                                                        )
                                                                                                        (vardecl
                                                                                                          go7
                                                                                                          (fun [List [[Tuple2 (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[These (con integer)] (con integer)]]]] [List [[Tuple2 (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]])
                                                                                                        )
                                                                                                        (lam
                                                                                                          ds1
                                                                                                          [List [[Tuple2 (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[These (con integer)] (con integer)]]]]
                                                                                                          [
                                                                                                            [
                                                                                                              [
                                                                                                                {
                                                                                                                  [
                                                                                                                    {
                                                                                                                      Nil_match
                                                                                                                      [[Tuple2 (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[These (con integer)] (con integer)]]]
                                                                                                                    }
                                                                                                                    ds1
                                                                                                                  ]
                                                                                                                  (fun Unit [List [[Tuple2 (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]])
                                                                                                                }
                                                                                                                (lam
                                                                                                                  thunk
                                                                                                                  Unit
                                                                                                                  {
                                                                                                                    Nil
                                                                                                                    [[Tuple2 (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]
                                                                                                                  }
                                                                                                                )
                                                                                                              ]
                                                                                                              (lam
                                                                                                                ds2
                                                                                                                [[Tuple2 (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[These (con integer)] (con integer)]]]
                                                                                                                (lam
                                                                                                                  xs
                                                                                                                  [List [[Tuple2 (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[These (con integer)] (con integer)]]]]
                                                                                                                  (lam
                                                                                                                    thunk
                                                                                                                    Unit
                                                                                                                    [
                                                                                                                      {
                                                                                                                        [
                                                                                                                          {
                                                                                                                            {
                                                                                                                              Tuple2_match
                                                                                                                              (con bytestring)
                                                                                                                            }
                                                                                                                            [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[These (con integer)] (con integer)]]
                                                                                                                          }
                                                                                                                          ds2
                                                                                                                        ]
                                                                                                                        [List [[Tuple2 (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]]
                                                                                                                      }
                                                                                                                      (lam
                                                                                                                        c
                                                                                                                        (con bytestring)
                                                                                                                        (lam
                                                                                                                          i
                                                                                                                          [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[These (con integer)] (con integer)]]
                                                                                                                          [
                                                                                                                            [
                                                                                                                              {
                                                                                                                                Cons
                                                                                                                                [[Tuple2 (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]
                                                                                                                              }
                                                                                                                              [
                                                                                                                                [
                                                                                                                                  {
                                                                                                                                    {
                                                                                                                                      Tuple2
                                                                                                                                      (con bytestring)
                                                                                                                                    }
                                                                                                                                    [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]
                                                                                                                                  }
                                                                                                                                  c
                                                                                                                                ]
                                                                                                                                (let
                                                                                                                                  (rec
                                                                                                                                  )
                                                                                                                                  (termbind
                                                                                                                                    (strict
                                                                                                                                    )
                                                                                                                                    (vardecl
                                                                                                                                      go8
                                                                                                                                      (fun [List [[Tuple2 (con bytestring)] [[These (con integer)] (con integer)]]] [List [[Tuple2 (con bytestring)] (con integer)]])
                                                                                                                                    )
                                                                                                                                    (lam
                                                                                                                                      ds4
                                                                                                                                      [List [[Tuple2 (con bytestring)] [[These (con integer)] (con integer)]]]
                                                                                                                                      [
                                                                                                                                        [
                                                                                                                                          [
                                                                                                                                            {
                                                                                                                                              [
                                                                                                                                                {
                                                                                                                                                  Nil_match
                                                                                                                                                  [[Tuple2 (con bytestring)] [[These (con integer)] (con integer)]]
                                                                                                                                                }
                                                                                                                                                ds4
                                                                                                                                              ]
                                                                                                                                              (fun Unit [List [[Tuple2 (con bytestring)] (con integer)]])
                                                                                                                                            }
                                                                                                                                            (lam
                                                                                                                                              thunk
                                                                                                                                              Unit
                                                                                                                                              {
                                                                                                                                                Nil
                                                                                                                                                [[Tuple2 (con bytestring)] (con integer)]
                                                                                                                                              }
                                                                                                                                            )
                                                                                                                                          ]
                                                                                                                                          (lam
                                                                                                                                            ds5
                                                                                                                                            [[Tuple2 (con bytestring)] [[These (con integer)] (con integer)]]
                                                                                                                                            (lam
                                                                                                                                              xs1
                                                                                                                                              [List [[Tuple2 (con bytestring)] [[These (con integer)] (con integer)]]]
                                                                                                                                              (lam
                                                                                                                                                thunk
                                                                                                                                                Unit
                                                                                                                                                [
                                                                                                                                                  {
                                                                                                                                                    [
                                                                                                                                                      {
                                                                                                                                                        {
                                                                                                                                                          Tuple2_match
                                                                                                                                                          (con bytestring)
                                                                                                                                                        }
                                                                                                                                                        [[These (con integer)] (con integer)]
                                                                                                                                                      }
                                                                                                                                                      ds5
                                                                                                                                                    ]
                                                                                                                                                    [List [[Tuple2 (con bytestring)] (con integer)]]
                                                                                                                                                  }
                                                                                                                                                  (lam
                                                                                                                                                    c1
                                                                                                                                                    (con bytestring)
                                                                                                                                                    (lam
                                                                                                                                                      i1
                                                                                                                                                      [[These (con integer)] (con integer)]
                                                                                                                                                      [
                                                                                                                                                        [
                                                                                                                                                          {
                                                                                                                                                            Cons
                                                                                                                                                            [[Tuple2 (con bytestring)] (con integer)]
                                                                                                                                                          }
                                                                                                                                                          [
                                                                                                                                                            [
                                                                                                                                                              {
                                                                                                                                                                {
                                                                                                                                                                  Tuple2
                                                                                                                                                                  (con bytestring)
                                                                                                                                                                }
                                                                                                                                                                (con integer)
                                                                                                                                                              }
                                                                                                                                                              c1
                                                                                                                                                            ]
                                                                                                                                                            [
                                                                                                                                                              [
                                                                                                                                                                [
                                                                                                                                                                  {
                                                                                                                                                                    [
                                                                                                                                                                      {
                                                                                                                                                                        {
                                                                                                                                                                          These_match
                                                                                                                                                                          (con integer)
                                                                                                                                                                        }
                                                                                                                                                                        (con integer)
                                                                                                                                                                      }
                                                                                                                                                                      i1
                                                                                                                                                                    ]
                                                                                                                                                                    (con integer)
                                                                                                                                                                  }
                                                                                                                                                                  (lam
                                                                                                                                                                    b
                                                                                                                                                                    (con integer)
                                                                                                                                                                    [
                                                                                                                                                                      [
                                                                                                                                                                        f
                                                                                                                                                                        (con
                                                                                                                                                                          0
                                                                                                                                                                        )
                                                                                                                                                                      ]
                                                                                                                                                                      b
                                                                                                                                                                    ]
                                                                                                                                                                  )
                                                                                                                                                                ]
                                                                                                                                                                (lam
                                                                                                                                                                  a
                                                                                                                                                                  (con integer)
                                                                                                                                                                  (lam
                                                                                                                                                                    b
                                                                                                                                                                    (con integer)
                                                                                                                                                                    [
                                                                                                                                                                      [
                                                                                                                                                                        f
                                                                                                                                                                        a
                                                                                                                                                                      ]
                                                                                                                                                                      b
                                                                                                                                                                    ]
                                                                                                                                                                  )
                                                                                                                                                                )
                                                                                                                                                              ]
                                                                                                                                                              (lam
                                                                                                                                                                a
                                                                                                                                                                (con integer)
                                                                                                                                                                [
                                                                                                                                                                  [
                                                                                                                                                                    f
                                                                                                                                                                    a
                                                                                                                                                                  ]
                                                                                                                                                                  (con
                                                                                                                                                                    0
                                                                                                                                                                  )
                                                                                                                                                                ]
                                                                                                                                                              )
                                                                                                                                                            ]
                                                                                                                                                          ]
                                                                                                                                                        ]
                                                                                                                                                        [
                                                                                                                                                          go8
                                                                                                                                                          xs1
                                                                                                                                                        ]
                                                                                                                                                      ]
                                                                                                                                                    )
                                                                                                                                                  )
                                                                                                                                                ]
                                                                                                                                              )
                                                                                                                                            )
                                                                                                                                          )
                                                                                                                                        ]
                                                                                                                                        Unit
                                                                                                                                      ]
                                                                                                                                    )
                                                                                                                                  )
                                                                                                                                  [
                                                                                                                                    go8
                                                                                                                                    i
                                                                                                                                  ]
                                                                                                                                )
                                                                                                                              ]
                                                                                                                            ]
                                                                                                                            [
                                                                                                                              go7
                                                                                                                              xs
                                                                                                                            ]
                                                                                                                          ]
                                                                                                                        )
                                                                                                                      )
                                                                                                                    ]
                                                                                                                  )
                                                                                                                )
                                                                                                              )
                                                                                                            ]
                                                                                                            Unit
                                                                                                          ]
                                                                                                        )
                                                                                                      )
                                                                                                      [
                                                                                                        go7
                                                                                                        [
                                                                                                          [
                                                                                                            unionVal
                                                                                                            ls
                                                                                                          ]
                                                                                                          rs
                                                                                                        ]
                                                                                                      ]
                                                                                                    )
                                                                                                  )
                                                                                                )
                                                                                              )
                                                                                            )
                                                                                            (let
                                                                                              (nonrec
                                                                                              )
                                                                                              (termbind
                                                                                                (strict
                                                                                                )
                                                                                                (vardecl
                                                                                                  wvalueLockedBy
                                                                                                  (fun [List PendingTxOut] (fun (con bytestring) [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]))
                                                                                                )
                                                                                                (lam
                                                                                                  ww
                                                                                                  [List PendingTxOut]
                                                                                                  (lam
                                                                                                    w
                                                                                                    (con bytestring)
                                                                                                    (let
                                                                                                      (rec
                                                                                                      )
                                                                                                      (termbind
                                                                                                        (strict
                                                                                                        )
                                                                                                        (vardecl
                                                                                                          go4
                                                                                                          (fun [List [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]])
                                                                                                        )
                                                                                                        (lam
                                                                                                          ds
                                                                                                          [List [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]]
                                                                                                          [
                                                                                                            [
                                                                                                              [
                                                                                                                {
                                                                                                                  [
                                                                                                                    {
                                                                                                                      Nil_match
                                                                                                                      [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]
                                                                                                                    }
                                                                                                                    ds
                                                                                                                  ]
                                                                                                                  (fun Unit [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]])
                                                                                                                }
                                                                                                                (lam
                                                                                                                  thunk
                                                                                                                  Unit
                                                                                                                  {
                                                                                                                    Nil
                                                                                                                    [[Tuple2 (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]
                                                                                                                  }
                                                                                                                )
                                                                                                              ]
                                                                                                              (lam
                                                                                                                y
                                                                                                                [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]
                                                                                                                (lam
                                                                                                                  ys
                                                                                                                  [List [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]]
                                                                                                                  (lam
                                                                                                                    thunk
                                                                                                                    Unit
                                                                                                                    [
                                                                                                                      [
                                                                                                                        [
                                                                                                                          unionWith
                                                                                                                          addInteger
                                                                                                                        ]
                                                                                                                        y
                                                                                                                      ]
                                                                                                                      [
                                                                                                                        go4
                                                                                                                        ys
                                                                                                                      ]
                                                                                                                    ]
                                                                                                                  )
                                                                                                                )
                                                                                                              )
                                                                                                            ]
                                                                                                            Unit
                                                                                                          ]
                                                                                                        )
                                                                                                      )
                                                                                                      [
                                                                                                        go4
                                                                                                        [
                                                                                                          [
                                                                                                            {
                                                                                                              {
                                                                                                                map
                                                                                                                [[Tuple2 (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]]
                                                                                                              }
                                                                                                              [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]
                                                                                                            }
                                                                                                            {
                                                                                                              {
                                                                                                                snd
                                                                                                                (con bytestring)
                                                                                                              }
                                                                                                              [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]
                                                                                                            }
                                                                                                          ]
                                                                                                          [
                                                                                                            [
                                                                                                              wscriptOutputsAt
                                                                                                              w
                                                                                                            ]
                                                                                                            ww
                                                                                                          ]
                                                                                                        ]
                                                                                                      ]
                                                                                                    )
                                                                                                  )
                                                                                                )
                                                                                              )
                                                                                              (let
                                                                                                (nonrec
                                                                                                )
                                                                                                (termbind
                                                                                                  (strict
                                                                                                  )
                                                                                                  (vardecl
                                                                                                    valueLockedBy
                                                                                                    (fun PendingTx (fun (con bytestring) [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]))
                                                                                                  )
                                                                                                  (lam
                                                                                                    w
                                                                                                    PendingTx
                                                                                                    (lam
                                                                                                      w25
                                                                                                      (con bytestring)
                                                                                                      [
                                                                                                        {
                                                                                                          [
                                                                                                            PendingTx_match
                                                                                                            w
                                                                                                          ]
                                                                                                          [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]
                                                                                                        }
                                                                                                        (lam
                                                                                                          ww1
                                                                                                          [List PendingTxIn]
                                                                                                          (lam
                                                                                                            ww2
                                                                                                            [List PendingTxOut]
                                                                                                            (lam
                                                                                                              ww3
                                                                                                              (con integer)
                                                                                                              (lam
                                                                                                                ww4
                                                                                                                [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]
                                                                                                                (lam
                                                                                                                  ww5
                                                                                                                  PendingTxIn
                                                                                                                  (lam
                                                                                                                    ww6
                                                                                                                    [Interval (con integer)]
                                                                                                                    (lam
                                                                                                                      ww7
                                                                                                                      [List [[Tuple2 (con bytestring)] (con bytestring)]]
                                                                                                                      (lam
                                                                                                                        ww8
                                                                                                                        (con bytestring)
                                                                                                                        [
                                                                                                                          [
                                                                                                                            wvalueLockedBy
                                                                                                                            ww2
                                                                                                                          ]
                                                                                                                          w25
                                                                                                                        ]
                                                                                                                      )
                                                                                                                    )
                                                                                                                  )
                                                                                                                )
                                                                                                              )
                                                                                                            )
                                                                                                          )
                                                                                                        )
                                                                                                      ]
                                                                                                    )
                                                                                                  )
                                                                                                )
                                                                                                (let
                                                                                                  (nonrec
                                                                                                  )
                                                                                                  (termbind
                                                                                                    (strict
                                                                                                    )
                                                                                                    (vardecl
                                                                                                      valueOf
                                                                                                      (fun [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]] (fun (con bytestring) (fun (con bytestring) (con integer))))
                                                                                                    )
                                                                                                    (lam
                                                                                                      ds
                                                                                                      [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]
                                                                                                      (lam
                                                                                                        cur
                                                                                                        (con bytestring)
                                                                                                        (lam
                                                                                                          tn
                                                                                                          (con bytestring)
                                                                                                          (let
                                                                                                            (nonrec
                                                                                                            )
                                                                                                            (termbind
                                                                                                              (strict
                                                                                                              )
                                                                                                              (vardecl
                                                                                                                j
                                                                                                                (fun [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)] (con integer))
                                                                                                              )
                                                                                                              (lam
                                                                                                                i
                                                                                                                [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]
                                                                                                                (let
                                                                                                                  (rec
                                                                                                                  )
                                                                                                                  (termbind
                                                                                                                    (strict
                                                                                                                    )
                                                                                                                    (vardecl
                                                                                                                      go7
                                                                                                                      (fun [List [[Tuple2 (con bytestring)] (con integer)]] (con integer))
                                                                                                                    )
                                                                                                                    (lam
                                                                                                                      ds1
                                                                                                                      [List [[Tuple2 (con bytestring)] (con integer)]]
                                                                                                                      [
                                                                                                                        [
                                                                                                                          {
                                                                                                                            [
                                                                                                                              {
                                                                                                                                Nil_match
                                                                                                                                [[Tuple2 (con bytestring)] (con integer)]
                                                                                                                              }
                                                                                                                              ds1
                                                                                                                            ]
                                                                                                                            (con integer)
                                                                                                                          }
                                                                                                                          (con
                                                                                                                            0
                                                                                                                          )
                                                                                                                        ]
                                                                                                                        (lam
                                                                                                                          ds2
                                                                                                                          [[Tuple2 (con bytestring)] (con integer)]
                                                                                                                          (lam
                                                                                                                            xs
                                                                                                                            [List [[Tuple2 (con bytestring)] (con integer)]]
                                                                                                                            [
                                                                                                                              {
                                                                                                                                [
                                                                                                                                  {
                                                                                                                                    {
                                                                                                                                      Tuple2_match
                                                                                                                                      (con bytestring)
                                                                                                                                    }
                                                                                                                                    (con integer)
                                                                                                                                  }
                                                                                                                                  ds2
                                                                                                                                ]
                                                                                                                                (con integer)
                                                                                                                              }
                                                                                                                              (lam
                                                                                                                                c
                                                                                                                                (con bytestring)
                                                                                                                                (lam
                                                                                                                                  i1
                                                                                                                                  (con integer)
                                                                                                                                  [
                                                                                                                                    [
                                                                                                                                      [
                                                                                                                                        {
                                                                                                                                          [
                                                                                                                                            Bool_match
                                                                                                                                            [
                                                                                                                                              [
                                                                                                                                                equalsByteString
                                                                                                                                                c
                                                                                                                                              ]
                                                                                                                                              tn
                                                                                                                                            ]
                                                                                                                                          ]
                                                                                                                                          (fun Unit (con integer))
                                                                                                                                        }
                                                                                                                                        (lam
                                                                                                                                          thunk
                                                                                                                                          Unit
                                                                                                                                          i1
                                                                                                                                        )
                                                                                                                                      ]
                                                                                                                                      (lam
                                                                                                                                        thunk
                                                                                                                                        Unit
                                                                                                                                        [
                                                                                                                                          go7
                                                                                                                                          xs
                                                                                                                                        ]
                                                                                                                                      )
                                                                                                                                    ]
                                                                                                                                    Unit
                                                                                                                                  ]
                                                                                                                                )
                                                                                                                              )
                                                                                                                            ]
                                                                                                                          )
                                                                                                                        )
                                                                                                                      ]
                                                                                                                    )
                                                                                                                  )
                                                                                                                  [
                                                                                                                    go7
                                                                                                                    i
                                                                                                                  ]
                                                                                                                )
                                                                                                              )
                                                                                                            )
                                                                                                            (let
                                                                                                              (rec
                                                                                                              )
                                                                                                              (termbind
                                                                                                                (strict
                                                                                                                )
                                                                                                                (vardecl
                                                                                                                  go7
                                                                                                                  (fun [List [[Tuple2 (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]] (con integer))
                                                                                                                )
                                                                                                                (lam
                                                                                                                  ds1
                                                                                                                  [List [[Tuple2 (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]]
                                                                                                                  [
                                                                                                                    [
                                                                                                                      {
                                                                                                                        [
                                                                                                                          {
                                                                                                                            Nil_match
                                                                                                                            [[Tuple2 (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]
                                                                                                                          }
                                                                                                                          ds1
                                                                                                                        ]
                                                                                                                        (con integer)
                                                                                                                      }
                                                                                                                      (con
                                                                                                                        0
                                                                                                                      )
                                                                                                                    ]
                                                                                                                    (lam
                                                                                                                      ds2
                                                                                                                      [[Tuple2 (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]
                                                                                                                      (lam
                                                                                                                        xs
                                                                                                                        [List [[Tuple2 (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]]
                                                                                                                        [
                                                                                                                          {
                                                                                                                            [
                                                                                                                              {
                                                                                                                                {
                                                                                                                                  Tuple2_match
                                                                                                                                  (con bytestring)
                                                                                                                                }
                                                                                                                                [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]
                                                                                                                              }
                                                                                                                              ds2
                                                                                                                            ]
                                                                                                                            (con integer)
                                                                                                                          }
                                                                                                                          (lam
                                                                                                                            c
                                                                                                                            (con bytestring)
                                                                                                                            (lam
                                                                                                                              i
                                                                                                                              [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]
                                                                                                                              [
                                                                                                                                [
                                                                                                                                  [
                                                                                                                                    {
                                                                                                                                      [
                                                                                                                                        Bool_match
                                                                                                                                        [
                                                                                                                                          [
                                                                                                                                            equalsByteString
                                                                                                                                            c
                                                                                                                                          ]
                                                                                                                                          cur
                                                                                                                                        ]
                                                                                                                                      ]
                                                                                                                                      (fun Unit (con integer))
                                                                                                                                    }
                                                                                                                                    (lam
                                                                                                                                      thunk
                                                                                                                                      Unit
                                                                                                                                      [
                                                                                                                                        j
                                                                                                                                        i
                                                                                                                                      ]
                                                                                                                                    )
                                                                                                                                  ]
                                                                                                                                  (lam
                                                                                                                                    thunk
                                                                                                                                    Unit
                                                                                                                                    [
                                                                                                                                      go7
                                                                                                                                      xs
                                                                                                                                    ]
                                                                                                                                  )
                                                                                                                                ]
                                                                                                                                Unit
                                                                                                                              ]
                                                                                                                            )
                                                                                                                          )
                                                                                                                        ]
                                                                                                                      )
                                                                                                                    )
                                                                                                                  ]
                                                                                                                )
                                                                                                              )
                                                                                                              [
                                                                                                                go7
                                                                                                                ds
                                                                                                              ]
                                                                                                            )
                                                                                                          )
                                                                                                        )
                                                                                                      )
                                                                                                    )
                                                                                                  )
                                                                                                  (let
                                                                                                    (nonrec
                                                                                                    )
                                                                                                    (termbind
                                                                                                      (strict
                                                                                                      )
                                                                                                      (vardecl
                                                                                                        mkValidator
                                                                                                        (fun Future (fun FutureData (fun FutureRedeemer (fun PendingTx Bool))))
                                                                                                      )
                                                                                                      (lam
                                                                                                        ft
                                                                                                        Future
                                                                                                        (lam
                                                                                                          ds
                                                                                                          FutureData
                                                                                                          (lam
                                                                                                            r
                                                                                                            FutureRedeemer
                                                                                                            (lam
                                                                                                              p
                                                                                                              PendingTx
                                                                                                              [
                                                                                                                {
                                                                                                                  [
                                                                                                                    Future_match
                                                                                                                    ft
                                                                                                                  ]
                                                                                                                  Bool
                                                                                                                }
                                                                                                                (lam
                                                                                                                  ds1
                                                                                                                  (con integer)
                                                                                                                  (lam
                                                                                                                    ds2
                                                                                                                    (con integer)
                                                                                                                    (lam
                                                                                                                      ds3
                                                                                                                      (con integer)
                                                                                                                      (lam
                                                                                                                        ds4
                                                                                                                        (con integer)
                                                                                                                        (lam
                                                                                                                          ds5
                                                                                                                          (con bytestring)
                                                                                                                          (lam
                                                                                                                            ds6
                                                                                                                            (con integer)
                                                                                                                            [
                                                                                                                              {
                                                                                                                                [
                                                                                                                                  FutureData_match
                                                                                                                                  ds
                                                                                                                                ]
                                                                                                                                Bool
                                                                                                                              }
                                                                                                                              (lam
                                                                                                                                ds7
                                                                                                                                (con bytestring)
                                                                                                                                (lam
                                                                                                                                  ds8
                                                                                                                                  (con bytestring)
                                                                                                                                  (lam
                                                                                                                                    ds9
                                                                                                                                    (con integer)
                                                                                                                                    (lam
                                                                                                                                      ds10
                                                                                                                                      (con integer)
                                                                                                                                      (let
                                                                                                                                        (nonrec
                                                                                                                                        )
                                                                                                                                        (termbind
                                                                                                                                          (strict
                                                                                                                                          )
                                                                                                                                          (vardecl
                                                                                                                                            wild2
                                                                                                                                            PendingTx
                                                                                                                                          )
                                                                                                                                          p
                                                                                                                                        )
                                                                                                                                        [
                                                                                                                                          {
                                                                                                                                            [
                                                                                                                                              PendingTx_match
                                                                                                                                              p
                                                                                                                                            ]
                                                                                                                                            Bool
                                                                                                                                          }
                                                                                                                                          (lam
                                                                                                                                            ds11
                                                                                                                                            [List PendingTxIn]
                                                                                                                                            (lam
                                                                                                                                              ds12
                                                                                                                                              [List PendingTxOut]
                                                                                                                                              (lam
                                                                                                                                                ds13
                                                                                                                                                (con integer)
                                                                                                                                                (lam
                                                                                                                                                  ds14
                                                                                                                                                  [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]
                                                                                                                                                  (lam
                                                                                                                                                    ds15
                                                                                                                                                    PendingTxIn
                                                                                                                                                    (lam
                                                                                                                                                      ds16
                                                                                                                                                      [Interval (con integer)]
                                                                                                                                                      (lam
                                                                                                                                                        ds17
                                                                                                                                                        [List [[Tuple2 (con bytestring)] (con bytestring)]]
                                                                                                                                                        (lam
                                                                                                                                                          ds18
                                                                                                                                                          (con bytestring)
                                                                                                                                                          (let
                                                                                                                                                            (nonrec
                                                                                                                                                            )
                                                                                                                                                            (termbind
                                                                                                                                                              (strict
                                                                                                                                                              )
                                                                                                                                                              (vardecl
                                                                                                                                                                paidOutTo1
                                                                                                                                                                (fun (con integer) (fun (con bytestring) (fun PendingTxOut Bool)))
                                                                                                                                                              )
                                                                                                                                                              (lam
                                                                                                                                                                vl
                                                                                                                                                                (con integer)
                                                                                                                                                                (lam
                                                                                                                                                                  pk
                                                                                                                                                                  (con bytestring)
                                                                                                                                                                  (lam
                                                                                                                                                                    txo
                                                                                                                                                                    PendingTxOut
                                                                                                                                                                    [
                                                                                                                                                                      {
                                                                                                                                                                        [
                                                                                                                                                                          PendingTxOut_match
                                                                                                                                                                          txo
                                                                                                                                                                        ]
                                                                                                                                                                        Bool
                                                                                                                                                                      }
                                                                                                                                                                      (lam
                                                                                                                                                                        ds19
                                                                                                                                                                        [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]
                                                                                                                                                                        (lam
                                                                                                                                                                          ds20
                                                                                                                                                                          [Maybe [[Tuple2 (con bytestring)] (con bytestring)]]
                                                                                                                                                                          (lam
                                                                                                                                                                            ds21
                                                                                                                                                                            PendingTxOutType
                                                                                                                                                                            [
                                                                                                                                                                              [
                                                                                                                                                                                [
                                                                                                                                                                                  {
                                                                                                                                                                                    [
                                                                                                                                                                                      PendingTxOutType_match
                                                                                                                                                                                      ds21
                                                                                                                                                                                    ]
                                                                                                                                                                                    (fun Unit Bool)
                                                                                                                                                                                  }
                                                                                                                                                                                  (lam
                                                                                                                                                                                    thunk
                                                                                                                                                                                    Unit
                                                                                                                                                                                    False
                                                                                                                                                                                  )
                                                                                                                                                                                ]
                                                                                                                                                                                (lam
                                                                                                                                                                                  pk1
                                                                                                                                                                                  (con bytestring)
                                                                                                                                                                                  (lam
                                                                                                                                                                                    thunk
                                                                                                                                                                                    Unit
                                                                                                                                                                                    [
                                                                                                                                                                                      [
                                                                                                                                                                                        [
                                                                                                                                                                                          {
                                                                                                                                                                                            [
                                                                                                                                                                                              Bool_match
                                                                                                                                                                                              [
                                                                                                                                                                                                [
                                                                                                                                                                                                  equalsByteString
                                                                                                                                                                                                  pk
                                                                                                                                                                                                ]
                                                                                                                                                                                                pk1
                                                                                                                                                                                              ]
                                                                                                                                                                                            ]
                                                                                                                                                                                            (fun Unit Bool)
                                                                                                                                                                                          }
                                                                                                                                                                                          (lam
                                                                                                                                                                                            thunk
                                                                                                                                                                                            Unit
                                                                                                                                                                                            [
                                                                                                                                                                                              [
                                                                                                                                                                                                equalsInteger
                                                                                                                                                                                                vl
                                                                                                                                                                                              ]
                                                                                                                                                                                              [
                                                                                                                                                                                                [
                                                                                                                                                                                                  [
                                                                                                                                                                                                    valueOf
                                                                                                                                                                                                    ds19
                                                                                                                                                                                                  ]
                                                                                                                                                                                                  emptyByteString
                                                                                                                                                                                                ]
                                                                                                                                                                                                emptyByteString
                                                                                                                                                                                              ]
                                                                                                                                                                                            ]
                                                                                                                                                                                          )
                                                                                                                                                                                        ]
                                                                                                                                                                                        (lam
                                                                                                                                                                                          thunk
                                                                                                                                                                                          Unit
                                                                                                                                                                                          False
                                                                                                                                                                                        )
                                                                                                                                                                                      ]
                                                                                                                                                                                      Unit
                                                                                                                                                                                    ]
                                                                                                                                                                                  )
                                                                                                                                                                                )
                                                                                                                                                                              ]
                                                                                                                                                                              Unit
                                                                                                                                                                            ]
                                                                                                                                                                          )
                                                                                                                                                                        )
                                                                                                                                                                      )
                                                                                                                                                                    ]
                                                                                                                                                                  )
                                                                                                                                                                )
                                                                                                                                                              )
                                                                                                                                                            )
                                                                                                                                                            [
                                                                                                                                                              [
                                                                                                                                                                [
                                                                                                                                                                  {
                                                                                                                                                                    [
                                                                                                                                                                      FutureRedeemer_match
                                                                                                                                                                      r
                                                                                                                                                                    ]
                                                                                                                                                                    (fun Unit Bool)
                                                                                                                                                                  }
                                                                                                                                                                  (lam
                                                                                                                                                                    thunk
                                                                                                                                                                    Unit
                                                                                                                                                                    [
                                                                                                                                                                      [
                                                                                                                                                                        greaterThanInteger
                                                                                                                                                                        [
                                                                                                                                                                          [
                                                                                                                                                                            [
                                                                                                                                                                              valueOf
                                                                                                                                                                              [
                                                                                                                                                                                [
                                                                                                                                                                                  valueLockedBy
                                                                                                                                                                                  wild2
                                                                                                                                                                                ]
                                                                                                                                                                                [
                                                                                                                                                                                  {
                                                                                                                                                                                    [
                                                                                                                                                                                      PendingTxIn_match
                                                                                                                                                                                      ds15
                                                                                                                                                                                    ]
                                                                                                                                                                                    (con bytestring)
                                                                                                                                                                                  }
                                                                                                                                                                                  (lam
                                                                                                                                                                                    ds19
                                                                                                                                                                                    PendingTxOutRef
                                                                                                                                                                                    (lam
                                                                                                                                                                                      ds20
                                                                                                                                                                                      [Maybe [[Tuple2 (con bytestring)] (con bytestring)]]
                                                                                                                                                                                      (lam
                                                                                                                                                                                        ds21
                                                                                                                                                                                        [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] [[(lam k (type) (lam v (type) [List [[Tuple2 k] v]])) (con bytestring)] (con integer)]]
                                                                                                                                                                                        [
                                                                                                                                                                                          [
                                                                                                                                                                                            [
                                                                                                                                                                                              {
                                                                                                                                                                                                [
                                                                                                                                                                                                  {
                                                                                                                                                                                                    Maybe_match
                                                                                                                                                                                                    [[Tuple2 (con bytestring)] (con bytestring)]
                                                                                                                                                                                                  }
                                                                                                                                                                                                  ds20
                                                                                                                                                                                                ]
                                                                                                                                                                                                (fun Unit (con bytestring))
                                                                                                                                                                                              }
                                                                                                                                                                                              (lam
                                                                                                                                                                                                h
                                                                                                                                                                                                [[Tuple2 (con bytestring)] (con bytestring)]
                                                                                                                                                                                                (lam
                                                                                                                                                                                                  thunk
                                                                                                                                                                                                  Unit
                                                                                                                                                                                                  [
                                                                                                                                                                                                    {
                                                                                                                                                                                                      [
                                                                                                                                                                                                        {
                                                                                                                                                                                                          {
                                                                                                                                                                                                            Tuple2_match
                                                                                                                                                                                                            (con bytestring)
                                                                                                                                                                                                          }
                                                                                                                                                                                                          (con bytestring)
                                                                                                                                                                                                        }
                                                                                                                                                                                                        h
                                                                                                                                                                                                      ]
                                                                                                                                                                                                      (con bytestring)
                                                                                                                                                                                                    }
                                                                                                                                                                                                    (lam
                                                                                                                                                                                                      a1
                                                                                                                                                                                                      (con bytestring)
                                                                                                                                                                                                      (lam
                                                                                                                                                                                                        ds22
                                                                                                                                                                                                        (con bytestring)
                                                                                                                                                                                                        a1
                                                                                                                                                                                                      )
                                                                                                                                                                                                    )
                                                                                                                                                                                                  ]
                                                                                                                                                                                                )
                                                                                                                                                                                              )
                                                                                                                                                                                            ]
                                                                                                                                                                                            (lam
                                                                                                                                                                                              thunk
                                                                                                                                                                                              Unit
                                                                                                                                                                                              [
                                                                                                                                                                                                {
                                                                                                                                                                                                  [
                                                                                                                                                                                                    {
                                                                                                                                                                                                      {
                                                                                                                                                                                                        Tuple2_match
                                                                                                                                                                                                        (con bytestring)
                                                                                                                                                                                                      }
                                                                                                                                                                                                      (con bytestring)
                                                                                                                                                                                                    }
                                                                                                                                                                                                    [
                                                                                                                                                                                                      {
                                                                                                                                                                                                        error
                                                                                                                                                                                                        [[Tuple2 (con bytestring)] (con bytestring)]
                                                                                                                                                                                                      }
                                                                                                                                                                                                      Unit
                                                                                                                                                                                                    ]
                                                                                                                                                                                                  ]
                                                                                                                                                                                                  (con bytestring)
                                                                                                                                                                                                }
                                                                                                                                                                                                (lam
                                                                                                                                                                                                  a1
                                                                                                                                                                                                  (con bytestring)
                                                                                                                                                                                                  (lam
                                                                                                                                                                                                    ds22
                                                                                                                                                                                                    (con bytestring)
                                                                                                                                                                                                    a1
                                                                                                                                                                                                  )
                                                                                                                                                                                                )
                                                                                                                                                                                              ]
                                                                                                                                                                                            )
                                                                                                                                                                                          ]
                                                                                                                                                                                          Unit
                                                                                                                                                                                        ]
                                                                                                                                                                                      )
                                                                                                                                                                                    )
                                                                                                                                                                                  )
                                                                                                                                                                                ]
                                                                                                                                                                              ]
                                                                                                                                                                            ]
                                                                                                                                                                            emptyByteString
                                                                                                                                                                          ]
                                                                                                                                                                          emptyByteString
                                                                                                                                                                        ]
                                                                                                                                                                      ]
                                                                                                                                                                      [
                                                                                                                                                                        [
                                                                                                                                                                          addInteger
                                                                                                                                                                          ds10
                                                                                                                                                                        ]
                                                                                                                                                                        ds9
                                                                                                                                                                      ]
                                                                                                                                                                    ]
                                                                                                                                                                  )
                                                                                                                                                                ]
                                                                                                                                                                (lam
                                                                                                                                                                  ov
                                                                                                                                                                  [OracleValue (con integer)]
                                                                                                                                                                  (lam
                                                                                                                                                                    thunk
                                                                                                                                                                    Unit
                                                                                                                                                                    (let
                                                                                                                                                                      (nonrec
                                                                                                                                                                      )
                                                                                                                                                                      (termbind
                                                                                                                                                                        (nonstrict
                                                                                                                                                                        )
                                                                                                                                                                        (vardecl
                                                                                                                                                                          spotPrice
                                                                                                                                                                          (con integer)
                                                                                                                                                                        )
                                                                                                                                                                        [
                                                                                                                                                                          {
                                                                                                                                                                            [
                                                                                                                                                                              {
                                                                                                                                                                                OracleValue_match
                                                                                                                                                                                (con integer)
                                                                                                                                                                              }
                                                                                                                                                                              ov
                                                                                                                                                                            ]
                                                                                                                                                                            (con integer)
                                                                                                                                                                          }
                                                                                                                                                                          (lam
                                                                                                                                                                            pk
                                                                                                                                                                            (con bytestring)
                                                                                                                                                                            (lam
                                                                                                                                                                              h
                                                                                                                                                                              (con integer)
                                                                                                                                                                              (lam
                                                                                                                                                                                t
                                                                                                                                                                                (con integer)
                                                                                                                                                                                [
                                                                                                                                                                                  [
                                                                                                                                                                                    [
                                                                                                                                                                                      {
                                                                                                                                                                                        [
                                                                                                                                                                                          Bool_match
                                                                                                                                                                                          [
                                                                                                                                                                                            [
                                                                                                                                                                                              equalsByteString
                                                                                                                                                                                              pk
                                                                                                                                                                                            ]
                                                                                                                                                                                            ds5
                                                                                                                                                                                          ]
                                                                                                                                                                                        ]
                                                                                                                                                                                        (fun Unit (con integer))
                                                                                                                                                                                      }
                                                                                                                                                                                      (lam
                                                                                                                                                                                        thunk
                                                                                                                                                                                        Unit
                                                                                                                                                                                        t
                                                                                                                                                                                      )
                                                                                                                                                                                    ]
                                                                                                                                                                                    (lam
                                                                                                                                                                                      thunk
                                                                                                                                                                                      Unit
                                                                                                                                                                                      [
                                                                                                                                                                                        {
                                                                                                                                                                                          [
                                                                                                                                                                                            {
                                                                                                                                                                                              {
                                                                                                                                                                                                Tuple2_match
                                                                                                                                                                                                (con integer)
                                                                                                                                                                                              }
                                                                                                                                                                                              (con integer)
                                                                                                                                                                                            }
                                                                                                                                                                                            [
                                                                                                                                                                                              {
                                                                                                                                                                                                error
                                                                                                                                                                                                [[Tuple2 (con integer)] (con integer)]
                                                                                                                                                                                              }
                                                                                                                                                                                              Unit
                                                                                                                                                                                            ]
                                                                                                                                                                                          ]
                                                                                                                                                                                          (con integer)
                                                                                                                                                                                        }
                                                                                                                                                                                        (lam
                                                                                                                                                                                          ds19
                                                                                                                                                                                          (con integer)
                                                                                                                                                                                          (lam
                                                                                                                                                                                            b1
                                                                                                                                                                                            (con integer)
                                                                                                                                                                                            b1
                                                                                                                                                                                          )
                                                                                                                                                                                        )
                                                                                                                                                                                      ]
                                                                                                                                                                                    )
                                                                                                                                                                                  ]
                                                                                                                                                                                  Unit
                                                                                                                                                                                ]
                                                                                                                                                                              )
                                                                                                                                                                            )
                                                                                                                                                                          )
                                                                                                                                                                        ]
                                                                                                                                                                      )
                                                                                                                                                                      (let
                                                                                                                                                                        (nonrec
                                                                                                                                                                        )
                                                                                                                                                                        (termbind
                                                                                                                                                                          (nonstrict
                                                                                                                                                                          )
                                                                                                                                                                          (vardecl
                                                                                                                                                                            delta
                                                                                                                                                                            (con integer)
                                                                                                                                                                          )
                                                                                                                                                                          [
                                                                                                                                                                            [
                                                                                                                                                                              multiplyInteger
                                                                                                                                                                              ds2
                                                                                                                                                                            ]
                                                                                                                                                                            [
                                                                                                                                                                              [
                                                                                                                                                                                subtractInteger
                                                                                                                                                                                spotPrice
                                                                                                                                                                              ]
                                                                                                                                                                              ds3
                                                                                                                                                                            ]
                                                                                                                                                                          ]
                                                                                                                                                                        )
                                                                                                                                                                        (let
                                                                                                                                                                          (nonrec
                                                                                                                                                                          )
                                                                                                                                                                          (termbind
                                                                                                                                                                            (nonstrict
                                                                                                                                                                            )
                                                                                                                                                                            (vardecl
                                                                                                                                                                              expShort
                                                                                                                                                                              (con integer)
                                                                                                                                                                            )
                                                                                                                                                                            [
                                                                                                                                                                              [
                                                                                                                                                                                subtractInteger
                                                                                                                                                                                ds10
                                                                                                                                                                              ]
                                                                                                                                                                              delta
                                                                                                                                                                            ]
                                                                                                                                                                          )
                                                                                                                                                                          (let
                                                                                                                                                                            (nonrec
                                                                                                                                                                            )
                                                                                                                                                                            (termbind
                                                                                                                                                                              (nonstrict
                                                                                                                                                                              )
                                                                                                                                                                              (vardecl
                                                                                                                                                                                expLong
                                                                                                                                                                                (con integer)
                                                                                                                                                                              )
                                                                                                                                                                              [
                                                                                                                                                                                [
                                                                                                                                                                                  addInteger
                                                                                                                                                                                  ds9
                                                                                                                                                                                ]
                                                                                                                                                                                delta
                                                                                                                                                                              ]
                                                                                                                                                                            )
                                                                                                                                                                            [
                                                                                                                                                                              [
                                                                                                                                                                                [
                                                                                                                                                                                  {
                                                                                                                                                                                    [
                                                                                                                                                                                      {
                                                                                                                                                                                        Nil_match
                                                                                                                                                                                        PendingTxOut
                                                                                                                                                                                      }
                                                                                                                                                                                      ds12
                                                                                                                                                                                    ]
                                                                                                                                                                                    (fun Unit Bool)
                                                                                                                                                                                  }
                                                                                                                                                                                  (lam
                                                                                                                                                                                    thunk
                                                                                                                                                                                    Unit
                                                                                                                                                                                    False
                                                                                                                                                                                  )
                                                                                                                                                                                ]
                                                                                                                                                                                (lam
                                                                                                                                                                                  o1
                                                                                                                                                                                  PendingTxOut
                                                                                                                                                                                  (lam
                                                                                                                                                                                    ds19
                                                                                                                                                                                    [List PendingTxOut]
                                                                                                                                                                                    (lam
                                                                                                                                                                                      thunk
                                                                                                                                                                                      Unit
                                                                                                                                                                                      [
                                                                                                                                                                                        [
                                                                                                                                                                                          [
                                                                                                                                                                                            {
                                                                                                                                                                                              [
                                                                                                                                                                                                {
                                                                                                                                                                                                  Nil_match
                                                                                                                                                                                                  PendingTxOut
                                                                                                                                                                                                }
                                                                                                                                                                                                ds19
                                                                                                                                                                                              ]
                                                                                                                                                                                              (fun Unit Bool)
                                                                                                                                                                                            }
                                                                                                                                                                                            (lam
                                                                                                                                                                                              thunk
                                                                                                                                                                                              Unit
                                                                                                                                                                                              (let
                                                                                                                                                                                                (nonrec
                                                                                                                                                                                                )
                                                                                                                                                                                                (termbind
                                                                                                                                                                                                  (nonstrict
                                                                                                                                                                                                  )
                                                                                                                                                                                                  (vardecl
                                                                                                                                                                                                    reqMargin
                                                                                                                                                                                                    (con integer)
                                                                                                                                                                                                  )
                                                                                                                                                                                                  [
                                                                                                                                                                                                    [
                                                                                                                                                                                                      addInteger
                                                                                                                                                                                                      ds6
                                                                                                                                                                                                    ]
                                                                                                                                                                                                    [
                                                                                                                                                                                                      [
                                                                                                                                                                                                        multiplyInteger
                                                                                                                                                                                                        ds2
                                                                                                                                                                                                      ]
                                                                                                                                                                                                      [
                                                                                                                                                                                                        [
                                                                                                                                                                                                          subtractInteger
                                                                                                                                                                                                          spotPrice
                                                                                                                                                                                                        ]
                                                                                                                                                                                                        ds3
                                                                                                                                                                                                      ]
                                                                                                                                                                                                    ]
                                                                                                                                                                                                  ]
                                                                                                                                                                                                )
                                                                                                                                                                                                (let
                                                                                                                                                                                                  (nonrec
                                                                                                                                                                                                  )
                                                                                                                                                                                                  (termbind
                                                                                                                                                                                                    (nonstrict
                                                                                                                                                                                                    )
                                                                                                                                                                                                    (vardecl
                                                                                                                                                                                                      totalMargin
                                                                                                                                                                                                      (con integer)
                                                                                                                                                                                                    )
                                                                                                                                                                                                    [
                                                                                                                                                                                                      [
                                                                                                                                                                                                        addInteger
                                                                                                                                                                                                        ds10
                                                                                                                                                                                                      ]
                                                                                                                                                                                                      ds9
                                                                                                                                                                                                    ]
                                                                                                                                                                                                  )
                                                                                                                                                                                                  (let
                                                                                                                                                                                                    (nonrec
                                                                                                                                                                                                    )
                                                                                                                                                                                                    (termbind
                                                                                                                                                                                                      (nonstrict
                                                                                                                                                                                                      )
                                                                                                                                                                                                      (vardecl
                                                                                                                                                                                                        j
                                                                                                                                                                                                        Bool
                                                                                                                                                                                                      )
                                                                                                                                                                                                      [
                                                                                                                                                                                                        [
                                                                                                                                                                                                          [
                                                                                                                                                                                                            {
                                                                                                                                                                                                              [
                                                                                                                                                                                                                Bool_match
                                                                                                                                                                                                                [
                                                                                                                                                                                                                  [
                                                                                                                                                                                                                    lessThanInteger
                                                                                                                                                                                                                    ds10
                                                                                                                                                                                                                  ]
                                                                                                                                                                                                                  reqMargin
                                                                                                                                                                                                                ]
                                                                                                                                                                                                              ]
                                                                                                                                                                                                              (fun Unit Bool)
                                                                                                                                                                                                            }
                                                                                                                                                                                                            (lam
                                                                                                                                                                                                              thunk
                                                                                                                                                                                                              Unit
                                                                                                                                                                                                              [
                                                                                                                                                                                                                [
                                                                                                                                                                                                                  [
                                                                                                                                                                                                                    paidOutTo1
                                                                                                                                                                                                                    totalMargin
                                                                                                                                                                                                                  ]
                                                                                                                                                                                                                  ds7
                                                                                                                                                                                                                ]
                                                                                                                                                                                                                o1
                                                                                                                                                                                                              ]
                                                                                                                                                                                                            )
                                                                                                                                                                                                          ]
                                                                                                                                                                                                          (lam
                                                                                                                                                                                                            thunk
                                                                                                                                                                                                            Unit
                                                                                                                                                                                                            False
                                                                                                                                                                                                          )
                                                                                                                                                                                                        ]
                                                                                                                                                                                                        Unit
                                                                                                                                                                                                      ]
                                                                                                                                                                                                    )
                                                                                                                                                                                                    [
                                                                                                                                                                                                      [
                                                                                                                                                                                                        [
                                                                                                                                                                                                          {
                                                                                                                                                                                                            [
                                                                                                                                                                                                              Bool_match
                                                                                                                                                                                                              [
                                                                                                                                                                                                                [
                                                                                                                                                                                                                  lessThanInteger
                                                                                                                                                                                                                  ds9
                                                                                                                                                                                                                ]
                                                                                                                                                                                                                reqMargin
                                                                                                                                                                                                              ]
                                                                                                                                                                                                            ]
                                                                                                                                                                                                            (fun Unit Bool)
                                                                                                                                                                                                          }
                                                                                                                                                                                                          (lam
                                                                                                                                                                                                            thunk
                                                                                                                                                                                                            Unit
                                                                                                                                                                                                            [
                                                                                                                                                                                                              [
                                                                                                                                                                                                                [
                                                                                                                                                                                                                  {
                                                                                                                                                                                                                    [
                                                                                                                                                                                                                      Bool_match
                                                                                                                                                                                                                      [
                                                                                                                                                                                                                        [
                                                                                                                                                                                                                          [
                                                                                                                                                                                                                            paidOutTo1
                                                                                                                                                                                                                            totalMargin
                                                                                                                                                                                                                          ]
                                                                                                                                                                                                                          ds8
                                                                                                                                                                                                                        ]
                                                                                                                                                                                                                        o1
                                                                                                                                                                                                                      ]
                                                                                                                                                                                                                    ]
                                                                                                                                                                                                                    (fun Unit Bool)
                                                                                                                                                                                                                  }
                                                                                                                                                                                                                  (lam
                                                                                                                                                                                                                    thunk
                                                                                                                                                                                                                    Unit
                                                                                                                                                                                                                    True
                                                                                                                                                                                                                  )
                                                                                                                                                                                                                ]
                                                                                                                                                                                                                (lam
                                                                                                                                                                                                                  thunk
                                                                                                                                                                                                                  Unit
                                                                                                                                                                                                                  j
                                                                                                                                                                                                                )
                                                                                                                                                                                                              ]
                                                                                                                                                                                                              Unit
                                                                                                                                                                                                            ]
                                                                                                                                                                                                          )
                                                                                                                                                                                                        ]
                                                                                                                                                                                                        (lam
                                                                                                                                                                                                          thunk
                                                                                                                                                                                                          Unit
                                                                                                                                                                                                          j
                                                                                                                                                                                                        )
                                                                                                                                                                                                      ]
                                                                                                                                                                                                      Unit
                                                                                                                                                                                                    ]
                                                                                                                                                                                                  )
                                                                                                                                                                                                )
                                                                                                                                                                                              )
                                                                                                                                                                                            )
                                                                                                                                                                                          ]
                                                                                                                                                                                          (lam
                                                                                                                                                                                            o2
                                                                                                                                                                                            PendingTxOut
                                                                                                                                                                                            (lam
                                                                                                                                                                                              ds20
                                                                                                                                                                                              [List PendingTxOut]
                                                                                                                                                                                              (lam
                                                                                                                                                                                                thunk
                                                                                                                                                                                                Unit
                                                                                                                                                                                                [
                                                                                                                                                                                                  [
                                                                                                                                                                                                    [
                                                                                                                                                                                                      {
                                                                                                                                                                                                        [
                                                                                                                                                                                                          Bool_match
                                                                                                                                                                                                          [
                                                                                                                                                                                                            [
                                                                                                                                                                                                              [
                                                                                                                                                                                                                {
                                                                                                                                                                                                                  member
                                                                                                                                                                                                                  (con integer)
                                                                                                                                                                                                                }
                                                                                                                                                                                                                fOrdSlot0
                                                                                                                                                                                                              ]
                                                                                                                                                                                                              ds1
                                                                                                                                                                                                            ]
                                                                                                                                                                                                            ds16
                                                                                                                                                                                                          ]
                                                                                                                                                                                                        ]
                                                                                                                                                                                                        (fun Unit Bool)
                                                                                                                                                                                                      }
                                                                                                                                                                                                      (lam
                                                                                                                                                                                                        thunk
                                                                                                                                                                                                        Unit
                                                                                                                                                                                                        (let
                                                                                                                                                                                                          (nonrec
                                                                                                                                                                                                          )
                                                                                                                                                                                                          (termbind
                                                                                                                                                                                                            (nonstrict
                                                                                                                                                                                                            )
                                                                                                                                                                                                            (vardecl
                                                                                                                                                                                                              j
                                                                                                                                                                                                              Bool
                                                                                                                                                                                                            )
                                                                                                                                                                                                            [
                                                                                                                                                                                                              [
                                                                                                                                                                                                                [
                                                                                                                                                                                                                  {
                                                                                                                                                                                                                    [
                                                                                                                                                                                                                      Bool_match
                                                                                                                                                                                                                      [
                                                                                                                                                                                                                        [
                                                                                                                                                                                                                          [
                                                                                                                                                                                                                            paidOutTo1
                                                                                                                                                                                                                            expShort
                                                                                                                                                                                                                          ]
                                                                                                                                                                                                                          ds8
                                                                                                                                                                                                                        ]
                                                                                                                                                                                                                        o2
                                                                                                                                                                                                                      ]
                                                                                                                                                                                                                    ]
                                                                                                                                                                                                                    (fun Unit Bool)
                                                                                                                                                                                                                  }
                                                                                                                                                                                                                  (lam
                                                                                                                                                                                                                    thunk
                                                                                                                                                                                                                    Unit
                                                                                                                                                                                                                    [
                                                                                                                                                                                                                      [
                                                                                                                                                                                                                        [
                                                                                                                                                                                                                          paidOutTo1
                                                                                                                                                                                                                          expLong
                                                                                                                                                                                                                        ]
                                                                                                                                                                                                                        ds7
                                                                                                                                                                                                                      ]
                                                                                                                                                                                                                      o1
                                                                                                                                                                                                                    ]
                                                                                                                                                                                                                  )
                                                                                                                                                                                                                ]
                                                                                                                                                                                                                (lam
                                                                                                                                                                                                                  thunk
                                                                                                                                                                                                                  Unit
                                                                                                                                                                                                                  False
                                                                                                                                                                                                                )
                                                                                                                                                                                                              ]
                                                                                                                                                                                                              Unit
                                                                                                                                                                                                            ]
                                                                                                                                                                                                          )
                                                                                                                                                                                                          [
                                                                                                                                                                                                            [
                                                                                                                                                                                                              [
                                                                                                                                                                                                                {
                                                                                                                                                                                                                  [
                                                                                                                                                                                                                    Bool_match
                                                                                                                                                                                                                    [
                                                                                                                                                                                                                      [
                                                                                                                                                                                                                        [
                                                                                                                                                                                                                          paidOutTo1
                                                                                                                                                                                                                          expShort
                                                                                                                                                                                                                        ]
                                                                                                                                                                                                                        ds8
                                                                                                                                                                                                                      ]
                                                                                                                                                                                                                      o1
                                                                                                                                                                                                                    ]
                                                                                                                                                                                                                  ]
                                                                                                                                                                                                                  (fun Unit Bool)
                                                                                                                                                                                                                }
                                                                                                                                                                                                                (lam
                                                                                                                                                                                                                  thunk
                                                                                                                                                                                                                  Unit
                                                                                                                                                                                                                  [
                                                                                                                                                                                                                    [
                                                                                                                                                                                                                      [
                                                                                                                                                                                                                        {
                                                                                                                                                                                                                          [
                                                                                                                                                                                                                            Bool_match
                                                                                                                                                                                                                            [
                                                                                                                                                                                                                              [
                                                                                                                                                                                                                                [
                                                                                                                                                                                                                                  paidOutTo1
                                                                                                                                                                                                                                  expLong
                                                                                                                                                                                                                                ]
                                                                                                                                                                                                                                ds7
                                                                                                                                                                                                                              ]
                                                                                                                                                                                                                              o2
                                                                                                                                                                                                                            ]
                                                                                                                                                                                                                          ]
                                                                                                                                                                                                                          (fun Unit Bool)
                                                                                                                                                                                                                        }
                                                                                                                                                                                                                        (lam
                                                                                                                                                                                                                          thunk
                                                                                                                                                                                                                          Unit
                                                                                                                                                                                                                          True
                                                                                                                                                                                                                        )
                                                                                                                                                                                                                      ]
                                                                                                                                                                                                                      (lam
                                                                                                                                                                                                                        thunk
                                                                                                                                                                                                                        Unit
                                                                                                                                                                                                                        j
                                                                                                                                                                                                                      )
                                                                                                                                                                                                                    ]
                                                                                                                                                                                                                    Unit
                                                                                                                                                                                                                  ]
                                                                                                                                                                                                                )
                                                                                                                                                                                                              ]
                                                                                                                                                                                                              (lam
                                                                                                                                                                                                                thunk
                                                                                                                                                                                                                Unit
                                                                                                                                                                                                                j
                                                                                                                                                                                                              )
                                                                                                                                                                                                            ]
                                                                                                                                                                                                            Unit
                                                                                                                                                                                                          ]
                                                                                                                                                                                                        )
                                                                                                                                                                                                      )
                                                                                                                                                                                                    ]
                                                                                                                                                                                                    (lam
                                                                                                                                                                                                      thunk
                                                                                                                                                                                                      Unit
                                                                                                                                                                                                      False
                                                                                                                                                                                                    )
                                                                                                                                                                                                  ]
                                                                                                                                                                                                  Unit
                                                                                                                                                                                                ]
                                                                                                                                                                                              )
                                                                                                                                                                                            )
                                                                                                                                                                                          )
                                                                                                                                                                                        ]
                                                                                                                                                                                        Unit
                                                                                                                                                                                      ]
                                                                                                                                                                                    )
                                                                                                                                                                                  )
                                                                                                                                                                                )
                                                                                                                                                                              ]
                                                                                                                                                                              Unit
                                                                                                                                                                            ]
                                                                                                                                                                          )
                                                                                                                                                                        )
                                                                                                                                                                      )
                                                                                                                                                                    )
                                                                                                                                                                  )
                                                                                                                                                                )
                                                                                                                                                              ]
                                                                                                                                                              Unit
                                                                                                                                                            ]
                                                                                                                                                          )
                                                                                                                                                        )
                                                                                                                                                      )
                                                                                                                                                    )
                                                                                                                                                  )
                                                                                                                                                )
                                                                                                                                              )
                                                                                                                                            )
                                                                                                                                          )
                                                                                                                                        ]
                                                                                                                                      )
                                                                                                                                    )
                                                                                                                                  )
                                                                                                                                )
                                                                                                                              )
                                                                                                                            ]
                                                                                                                          )
                                                                                                                        )
                                                                                                                      )
                                                                                                                    )
                                                                                                                  )
                                                                                                                )
                                                                                                              ]
                                                                                                            )
                                                                                                          )
                                                                                                        )
                                                                                                      )
                                                                                                    )
                                                                                                    mkValidator
                                                                                                  )
                                                                                                )
                                                                                              )
                                                                                            )
                                                                                          )
                                                                                        )
                                                                                      )
                                                                                    )
                                                                                  )
                                                                                )
                                                                              )
                                                                            )
                                                                          )
                                                                        )
                                                                      )
                                                                    )
                                                                  )
                                                                )
                                                              )
                                                            )
                                                          )
                                                        )
                                                      )
                                                    )
                                                  )
                                                )
                                              )
                                            )
                                          )
                                        )
                                      )
                                    )
                                  )
                                )
                              )
                            )
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  )
)