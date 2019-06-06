all: monstre

RegexTreeDumper.o: RegexTreeDumper.class PCREParser.jar
	gcj -c -O2 --classpath PCREParser.jar $<

RegexTreeDumper.class: RegexTreeDumper.java PCREParser.jar
	gcj -C -O2 --classpath PCREParser.jar $<

RegexTreeDumper.h: RegexTreeDumper.class
	gcjh $<

RegexTreeReduce.o: RegexTreeReduce.hs
	ghc -c -O -o $@ $<

PCREParser.jar: PCREParser/pom.xml PCREParser/src/main/antlr3/pcreparser/PCRE.g PCREParser/src/main/java/pcreparser/PCRE.java
	cd PCREParser; mvn install
	cp PCREParser/target/PCRE*.jar ./PCREParser.jar

PCREParser.o: PCREParser.jar
	gcj -c -O2 -o $@ $<

judge.cpp: judge.pyx
	cython3 --cplus -o $@ $<

judge.o: judge.cpp
	g++ -O2 -Wall `python3-config --cflags` -c -o $@ $<

monstre.o: monstre.cpp RegexTreeDumper.h RegexTreeReduce.o judge.cpp
	g++ -c -o $@ $< -O2 -std=c++11 -Wall -Wextra -I`ghc --print-libdir`/include `python3-config --cflags`

monstre: monstre.o RegexTreeDumper.o PCREParser.o RegexTreeReduce.o judge.o
	ghc -no-hs-main -o $@ $^ -lgcj -package json `python3-config --libs`

clean:
	rm -f *.hi *.o *.class *.so
	rm -f RegexTreeDumper.h RegexTreeReduce_stub.h judge.h
	rm -f PCREParser.jar
	rm -rf judge.cpp
	cd PCREParser; mvn clean
	rm -rf monstre
