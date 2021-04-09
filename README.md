# Test C - tc

Program, namenjen preverjanju testov za programski jezik C


Parametri
--

<pre>
tc.sh [-h] [clean|init] [&ltpot_do_testov>] &ltglavni_c_program> [&ltdodatni_c_program_1> ...]
    [ -t | -o | -T &ltn> | -f &lts> | -n &ltI> ] 

 funkcija:
    clean               Izbris diff in res datotek
    init                Generira .tcconfig datoteko v trenutnem imeniku

 -h, --help             Pomoč

 -t, --timed            Izpis časa

 -o, --show-output      Izpis izhoda programa

 -T &ltn>, --timeout &ltn>  Največje dovoljeno število sekund
                        izvajanja programa
                        Privzeto: '1'

 -n &ltI>                 Interval razpona obravnavanih primerov.
                        z menjavo - z ~ bo izbran komplement
                        a-b   (a, b]
                        a-    (a, ...)
                         -b   (..., b]
                         ~b   (b, ...)
                        a~b   (..., a]U(b, ...)
                        Privzeto: '-' (vsi)

 -f &lts>, --format &lts>   Format datotek za testiranje.
                        Privzeto: 'test'
 -e &ltf>, --entry &ltf>    Vhodna metoda c datoteke
                        Privzeto: 'main'
 -l &ltn>, --log &ltn>      Stopnja izpisa.
                        Možnosti: 1|2|3|4
                        1 - samo rezultati
                        2 - testi
                        3 - testi in prevajanje
                        4 - razhroščevanje
                        Privzeto:'3'
</pre>

Uporaba
--
 - Testiranje `.in` `.out`
```bash
# datoteke .in in .out se nahajajo v ./testi/,
# tc.sh in program.c pa v trenutnem imeniku. Zanima nas tudi čas izvedbe
$./tc.sh testi/ program.c -t

# Izhod
Using 6 test.in files.
 == COMPILING ==
Compiled program.c

 == TESTING ==
Test01 -- OK [0.27 s]
Test02 -- OK [0.11 s]
Test03 -- OK [0.15 s]
Test04 -- OK [0.14 s]
Test05 -- OK [0.13 s]
Test06 -- OK [0.13 s]
Result 6/6
```

 - Testiranje `.c` `.out`
```bash

# datoteke .c in .out se nahajajo v trenutnem imeniku,
# program.c pa nekje drugje. Čas izvedbe je podaljšan na 2 sekundi,
# testi so oblike primerXX.in, preverili pa bomo le prve dva
$ tc.sh /pot/do/program.c -f primer -T 2 -t -n -2

# Izhod
Using 2 primer.in files.
 == COMPILING ==
Compiled program.c

 == TESTING ==
Primer01 -- OK [0.21 s]
Primer02 -- OK [0.09 s]
Result 2/2
```
 - Testiranje šolskih primerov`.c` `.out`
```bash

# datoteke .c, .out in program.c se nahajajo v trenutnem imeniku.
# Čas izvedbe je podaljšan na 2 sekundi. Testi so oblike testXX.c
# Vhodna metoda je __main__
$ tc.sh program.c -f test -T 2 -t -e __main__

# Izhod
Using 6 test.c files.
 == COMPILING ==
Compiled test01.c
Compiled test02.c
Compiled test04.c
Compiled test05.c
Compiled test06.c

 == TESTING ==
Test01 -- OK
Test02 -- OK
Test04 -- OK
Test05 -- OK
Test06 -- OK
Result 6/6
```
- Čiščenje

```bash
# čiščenje vseh primerov oblike primerXX.diff in primerXX.res iz ./tests/
$./tc.sh clean tests/ -f primer

# Izhod
/pot/do/testov/primer01.res
/pot/do/testov/primer01.diff
/pot/do/testov/primer02.res
/pot/do/testov/primer02.diff
/pot/do/testov/primer03.res
/pot/do/testov/primer03.diff
Remove all [y/n]?
> y
```
