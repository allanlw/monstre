MonstRE
=======

MonstRE is a program for analyzing regular expressions for exponential 
blowup. The algorithm used is based on Kirrage, James, Asiri Rathnayake, and 
Hayo Thielecke. "Static analysis for regular expression denial-of-service 
attacks." Network and System Security. Springer Berlin Heidelberg, 2013. 
135-148. http://www.cs.bham.ac.uk/~hxt/research/reg-exp-sec.pdf

MonstRE gets its name from the fact that is implemented in about 5 different 
programming languages and is literally a monster.

First, the program is parsed in Java using an MIT-Licensed PCRE Parser, 
which returns a string that is a haskell expression. A haskell program reads 
this string (using the read monad) and does simplification on it to change 
it into a form that is similar to the reduced/simplified regular expression 
AST that is described in the paper. Finally, a python3 program performs the 
actual analysis.

To build, you probably want to use docker. Just run from this directory:

    sudo docker build -t monstre .
    sudo docker run -it monstre 'a*'

If you would like to build it locally for development, you will need the
packages that the dockerfile installs installed on your system. You can then
run make from the src directory.

Bugs
----

- Does not generate attack strings
- Only works on ascii printable bytes
- There is some error in the Java parser that makes in bork on some things containing :
- Only supports a constant number of recursions for {a,b} matches, after which it just uses a *
