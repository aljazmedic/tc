# Test C - tc

Program, namenjen preverjanju testov za programski jezik C


Parametri
--

```
tc.sh [-h] [<pot_do_testov>] <glavni_c_program> [<dodatni_c_program_1> ...]
    [-t | -T <n> | -f <s>] 

 -h, --help             Pomoč

 -t, --timed            Izpis časa

 -T <n>, --timeout <n>  Največje dovoljeno število sekund
                        izvajanja programa
                        Privzeto: '1'

 -f <s>, --format <s>   Format datotek za testiranje.
                        Privzeto: 'test'
```

Uporaba
--
 - Testiranje `.in` `.out`
```bash
# datoteke .in in .out se nahajajo v ./testi/,
# program pa v trenutnem imeniku. Zanima nas tudi čas izvedbe
$./tc.sh testi/ program.c -t

# Izhod
Using 6 .in files.
 == COMPILING ==
Prevedel program.c

 == TESTING ==
Test01 -- OK [0.27 s]
Test02 -- OK [0.11 s]
Test03 -- OK [0.15 s]
Test04 -- OK [0.14 s]
Test05 -- OK [0.13 s]
Test06 -- OK [0.13 s]
Rezultat 6/6
```

 - Testiranje `.c` `.out`
```bash

# datoteke .c in .out se nahajajo v trenutnem imeniku,
# program pa v drugem imeniku. Čas izvedbe je podaljšan na 2 sekundi,
# testi pa oblike primerXX
$../tc.sh program.c -f primer -T 2 -t

# Izhod
Using 2 .in files.
 == COMPILING ==
Compiled program.c

 == TESTING ==
Primer01 -- OK [0.21 s]
Primer02 -- OK [0.09 s]
Result 2/2
```

- Čiščenje

```bash
# čiščenje vseh primerov oblike primerXX.diff in primerXX.res iz ./tests/
$./tc.sh clean tests/ -f primer

# Izhod
/path/to/tests/primer01.res
/path/to/tests/primer01.diff
/path/to/tests/primer02.res
/path/to/tests/primer02.diff
/path/to/tests/primer03.res
/path/to/tests/primer03.diff
Remove all [y/n]? y
```