#include <cstring>
#include <cstdio>
#include <cstdlib>
#include <Python.h>
#include <gcj/cni.h>
#include <HsFFI.h>
#include <java/lang/String.h>
#include <java/lang/System.h>
#include <java/lang/Throwable.h>
#include <java/io/PrintStream.h>

#include "RegexTreeDumper.h"
#include "RegexTreeReduce_stub.h"
extern "C" {
#define DL_IMPORT(x) x
#include "judge.h"
#undef DL_IMPORT
}

using namespace std;

// Calls the gcj generated PCREParser wrapper code and returns a parsed tree
// that can be consumed by haskell Read
static char *dumpRegexTree(const char *regex) {
  using namespace java::lang;

  char *parsedTreeCStr = nullptr;

  String *target = JvNewStringUTF(regex);
  String *parsedTree = RegexTreeDumper::parse(target);
  parsedTreeCStr = (char *)calloc(sizeof(char), (JvGetStringUTFLength(parsedTree) + 1));
  JvGetStringUTFRegion(parsedTree, 0, parsedTree->length(), parsedTreeCStr);

  return parsedTreeCStr;
}

extern "C" {
// ghc required module initialization
// see https://downloads.haskell.org/~ghc/7.0.2/docs/html/users_guide/ffi-ghc.html
extern void __stginit_RegexTreeReduce (void);

static void init_vms(void) {
  using namespace java::lang;

  JvCreateJavaVM(NULL);
  JvAttachCurrentThread(NULL, NULL);
  JvInitClass(&System::class$);
  JvInitClass(&RegexTreeDumper::class$);

  char **my_argv = (char **)malloc(sizeof(char*));
  my_argv[0] = strdup("monstre");
  int my_argc = 1;

  hs_init(&my_argc, &my_argv);

  Py_Initialize();
  PyInit_judge();
}

static void destroy_vms(void) {
  hs_exit();
  Py_Finalize();
}

// Calls the ghc RegexTreeReduce module
static char *reduceTreeWrapper(const char *tree) {
  hs_add_root(__stginit_RegexTreeReduce);
  char *res = strdup((const char *)reduceTreeC((void *)tree));
  return res;
}

static char *judgeWrapper(const char *json, int verbose) {
  char * res = strdup(judgeC(json, verbose));
  return res;
}

}

static int check_regex(char *regex, int verbose) {
  char *parsedTreeCStr;
  try {
    parsedTreeCStr = dumpRegexTree(regex);
    if (verbose)
      puts(parsedTreeCStr);
  } catch (java::lang::Throwable *t) {
    if (verbose) {
      fflush(stdout);
      java::lang::System::out->println(JvNewStringUTF("Unhandled Java Exception:"));
      t->printStackTrace(java::lang::System::out);
      java::lang::System::out->flush();
    }
    return -1;
  }

  char *reducedTree = reduceTreeWrapper(parsedTreeCStr);
  if (verbose)
    puts(reducedTree);

  const char *haskellExceptionName = "UnhandledRegex";
  if (strncmp(reducedTree, haskellExceptionName, strlen(haskellExceptionName)) == 0)
    return -1;

  char *judgement = judgeWrapper(reducedTree, verbose);
  if (verbose)
    puts(judgement);

  if (strcmp(judgement, "error") == 0)
    return -1;

  return (!strcmp(judgement, "vulnerable"));
}

extern "C" int main(int argc, char *argv[]) {
  int c;
  int verbose = 0;

  while((c = getopt(argc, argv, "vh")) != -1) {
    switch(c) {
    case 'v':
      verbose = 1;
      break;
    case 'h':
    default:
      printf("Usage: %s [opts] [regex...]\n", argv[0]);
      printf("  -v          Print verbose/debugging information\n");
      printf("  -h          Print this help\n");
      printf("If any regexes had errors, returns 2\n");
      printf("If any regexes were vulnerable, return 1\n");
      printf("If all were fine, return 0\n");
      return 0;
    }
  }

  int vuln_count = 0, ok_count = 0, err_count = 0;

  init_vms();

  for (int i = optind; i < argc; i++) {
    if (argc - optind > 1) {
      printf("%s: ", argv[i]);
      fflush(stdout);
    }
    int res = check_regex(argv[i], verbose);
    switch (res) {
    case 1:
      puts("Vulnerable");
      vuln_count++;
      break;
    case 0:
      puts("Not vulnerable");
      ok_count++;
      break;
    default:
      puts("Analysis Error");
      err_count++;
      break;
    }
  }

  destroy_vms();

  if (err_count > 0)
    return 2;
  else if (vuln_count > 0)
    return 1;
  else
    return 0;
}
