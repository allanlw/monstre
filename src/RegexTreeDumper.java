import pcreparser.PCRE;
import pcreparser.PCREParser;
import org.antlr.runtime.tree.CommonTree;
import java.util.List;
import java.util.ArrayList;
import java.util.regex.Pattern;
import java.util.regex.Matcher;
import java.lang.StringBuilder;
import java.io.ByteArrayOutputStream;
import java.io.PrintStream;

public class RegexTreeDumper {
   public static String parse(String targetRegex) {
     // override System.Err, because antlr messes with it
     ByteArrayOutputStream output_bytes = new ByteArrayOutputStream();
     System.setErr(new PrintStream(output_bytes));

     PCRE parsed = new PCRE(targetRegex);
     if (output_bytes.size() != 0) {
       throw new RuntimeException(output_bytes.toString());
     }

     ArrayList<String> tokens = new ArrayList<String>();
     tokenizeTree(parsed.getCommonTree(), tokens);

     int level = 0;

     StringBuilder out = new StringBuilder();

     for (String token : tokens) {
       if (token.equals("]")) {
         out.append("\n");
         level -= 1;
         for (int i = 0; i < level; i++) {
           out.append("  ");
         }
       }
       out.append(token);
       if (token.equals("[")) {
         out.append("\n");
         level += 1;
         for (int i =0; i < level; i++) {
           out.append("  ");
         }
       } else if (!token.equals("]")) {
         out.append(" ");
       } else if (token.equals(",")) {
         out.append("\n");
         for (int i = 0; i < level; i++) {
           out.append("  ");
         }
       }
     }
     out.append("\n");

     return out.toString();
   }

  static void tokenizeTree(CommonTree tree, List<String> output) {
    String tokenName = PCREParser.tokenNames[tree.getType()];
    String tokenText = tree.getText();

    boolean isValue = (tokenName != tokenText);

    tokenName = tokenName.toLowerCase();
    tokenName = tokenName.substring(0,1).toUpperCase() + tokenName.substring(1);

    output.add("RE" + tokenName);
    if (tokenName.equals("Number")) {
      output.add(tokenText);
    } else if (isValue) {
      output.add("\""+ tokenText.replaceAll(Pattern.quote("\\"), Matcher.quoteReplacement("\\\\")).replaceAll(Pattern.quote("\""), Matcher.quoteReplacement("\\\"")) + "\"");
    }

    if (tree.getChildCount() > 0) {
      output.add("[");
      boolean first = true;
      for (Object child : tree.getChildren()) {
        if (!first) { output.add(","); }
        else { first = false; }
        tokenizeTree((CommonTree)child, output);
      }
      output.add("]");
    }
  }
}
