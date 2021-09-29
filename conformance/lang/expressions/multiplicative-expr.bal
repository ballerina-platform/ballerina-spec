Test-Case: output
Description: Test multiplication scenarios for different decimal values.
Labels: multiplicative-expr, numeric-literal, float-point-literal

public function main() {
     decimal a = 2.5E-17;
     decimal b = 2.5E+17;
     decimal c = b * a;
     io:println(c); // @output 6.25
     io:println(2.5E+17d * 2.5E-17d); // @output 6.25

     a = 1.423223E6d;
     b = 2.34413E2d;
     c = a * b;
     io:println(c); // @output 333621973.099
     io:println(1.423223E6d * 2.34413E2d); // @output 333621973.099

     a = 25.E1742d;
     b = 1.0d;
     c = a * b;
     io:println(c); // @output 2.5E+1743
     io:println(25.E1742d * 1.0d); // @output 2.5E+1743

     a = 25.E1742d;
     b = 0.0d;
     c = a * b;
     io:println(c); // @output 0
     io:println(25.E1742d * 0.0d); // @output 0

     a = 25.E17d;
     b = 0.9E-10;
     c = a * b;
     io:println(c); // @output 2.25E+8
     io:println(25.E17d * 0.9E-10d); // @output 2.25E+8

     a = -25.E17d;
     b = 0.9E-10;
     c = a * b;
     io:println(c); // @output -2.25E+8
     io:println(-25.E17d * 0.9E-10d); // @output -2.25E+8

     a = 17.E12d;
     b = 0.0d;
     c = a * b;
     io:println(c); // @output 0
     io:println(17.E12d * 0.0d); // @output 0

     a = -17.E12d;
     b = 0.0d;
     c = a * b;
     io:println(c); // @output 0
     io:println(-17.E12d * 0.0d); // @output 0

     a = 11.E12d;
     b = -0.0d;
     c = a * b;
     io:println(c); // @output 0
     io:println(11.E12d * -0.0d); // @output 0

     a = 17.E1290d;
     b = 13.E1521d;
     c = a * b;
     io:println(c); // @output 2.21E+2813
     io:println(17.E1290d * 13.E1521d); // @output 2.21E+2813

     a = 0.0d;
     b = 0.0d;
     c = a * b;
     io:println(c); // @output 0
     io:println(0.0d * 0.0d); // @output 0

     a = -0.0d;
     b = 0.0d;
     c = a * b;
     io:println(c); // @output 0
     io:println(-0.0d * 0.0d); // @output 0
}

Test-Case: output
Description: Test multiplication scenarios for different nillable decimal values.
Labels: multiplicative-expr, numeric-literal, float-point-literal

public function main() {
     decimal? a = 2.5E-17;
     decimal? b = 2.5E+17;
     decimal? c = b * a;
     io:println(c); // @output 6.25

     a = 1.423223E6d;
     b = 2.34413E2d;
     c = a * b;
     io:println(c); // @output 333621973.099

     a = 25.E1742d;
     b = 1.0d;
     c = a * b;
     io:println(c); // @output 2.5E+1743

     a = 25.E1742d;
     b = 0.0d;
     c = a * b;
     io:println(c); // @output 0

     a = 25.E17d;
     b = 0.9E-10;
     c = a * b;
     io:println(c); // @output 2.25E+8

     a = -25.E17d;
     b = 0.9E-10;
     c = a * b;
     io:println(c); // @output -2.25E+8

     a = 17.E12d;
     b = 0.0d;
     c = a * b;
     io:println(c); // @output 0

     a = -17.E12d;
     b = 0.0d;
     c = a * b;
     io:println(c); // @output 0

     a = 11.E12d;
     b = -0.0d;
     c = a * b;
     io:println(c); // @output 0

     a = 17.E1290d;
     b = 13.E1521d;
     c = a * b;
     io:println(c); // @output 2.21E+2813

     a = 0.0d;
     b = 0.0d;
     c = a * b;
     io:println(c); // @output 0

     a = -0.0d;
     b = 0.0d;
     c = a * b;
     io:println(c); // @output 0

     a = -0.0d;
     b = ();
     c = a * b;
     io:println(c.toBalString()); // @output ()

     a = ();
     b = 0.0d;
     c = a * b;
     io:println(c.toBalString()); // @output ()
}

Test-Case: output
Description: Test multiplication scenarios for different float values.
Labels: multiplicative-expr, numeric-literal, float-point-literal

public function main() {
     float a = 2.5E-17;
     float b = 2.5E+17;
     float c = b * a;
     io:println(c); // @output 6.25
     io:println(2.5E+17 * 2.5E-17); // @output 6.25

     a = 1.423223E6;
     b = 2.34413E2;
     c = a * b;
     io:println(c); // @output 3.3362197309900004E8
     io:println(1.423223E6 * 2.34413E2); // @output 3.3362197309900004E8

     a = 25.E1742f;
     b = 1.0f;
     c = a * b;
     io:println(c); // @output Infinity
     io:println(25.E1742f * 1.0f); // @output Infinity

     a = 1.7976931348623157e+308;
     b = 1.7976931348623157e+308;
     c = a * b;
     io:println(c); // @output Infinity
     io:println(1.7976931348623157e+308 * 1.7976931348623157e+308); // @output Infinity

     a = -1.7976931348623157e+308;
     b = 1.7976931348623157e+308;
     c = a * b;
     io:println(c); // @output -Infinity
     io:println(-1.7976931348623157e+308 * 1.7976931348623157e+308); // @output -Infinity

     a = 25.E1742f;
     b = 0.0f;
     c = a * b;
     io:println(c); // @output NaN
     io:println(25.E1742f * 0.0f); // @output NaN

     a = 25.E17f;
     b = 0.9E-10f;
     c = a * b;
     io:println(c); // @output 2.25E8
     io:println(25.E17f * 0.9E-10); // @output 2.25E8

     a = -25.E17f;
     b = 0.9E-10f;
     c = a * b;
     io:println(c); // @output -2.25E8
     io:println(-25.E17f * 0.9E-10); // @output -2.25E8

     a = 17.E12f;
     b = 0.0f;
     c = a * b;
     io:println(c); // @output 0.0
     io:println(17.E12f * 0.0f); // @output 0.0

     a = -17.E12f;
     b = 0.0f;
     c = a * b;
     io:println(c); // @output -0.0
     io:println(-17.E12f * 0.0f); // @output -0.0

     a = 11.E12f;
     b = -0.0f;
     c = a * b;
     io:println(c); // @output -0.0
     io:println(11.E12f * -0.0f); // @output -0.0

     a = 17.E1290f;
     b = 13.E1521f;
     c = a * b;
     io:println(c); // @output Infinity
     io:println(17.E1290f * 13.E1521f); // @output Infinity

     a = 0.0f;
     b = 0.0f;
     c = a * b;
     io:println(c); // @output 0.0
     io:println(0.0f * 0.0f); // @output 0.0

     a = -0.0f;
     b = 0.0f;
     c = a * b;
     io:println(c); // @output -0.0
     io:println(-0.0f * 0.0f); // @output -0.0
}

Test-Case: output
Description: Test multiplication scenarios for different nillable float values.
Labels: multiplicative-expr, numeric-literal, float-point-literal

public function main() {
     float? a = 2.5E-17;
     float? b = 2.5E+17;
     float? c = b * a;
     io:println(c); // @output 6.25

     a = 1.423223E6;
     b = 2.34413E2;
     c = a * b;
     io:println(c); // @output 3.3362197309900004E8

     a = 25.E1742f;
     b = 1.0f;
     c = a * b;
     io:println(c); // @output Infinity

     a = 1.7976931348623157e+308;
     b = 1.7976931348623157e+308;
     c = a * b;
     io:println(c); // @output Infinity

     a = -1.7976931348623157e+308;
     b = 1.7976931348623157e+308;
     c = a * b;
     io:println(c); // @output -Infinity

     a = 25.E1742f;
     b = 0.0f;
     c = a * b;
     io:println(c); // @output NaN

     a = 25.E17f;
     b = 0.9E-10f;
     c = a * b;
     io:println(c); // @output 2.25E8

     a = -25.E17f;
     b = 0.9E-10f;
     c = a * b;
     io:println(c); // @output -2.25E8

     a = 17.E12f;
     b = 0.0f;
     c = a * b;
     io:println(c); // @output 0.0

     a = -17.E12f;
     b = 0.0f;
     c = a * b;
     io:println(c); // @output -0.0

     a = 11.E12f;
     b = -0.0f;
     c = a * b;
     io:println(c); // @output -0.0

     a = 17.E1290f;
     b = 13.E1521f;
     c = a * b;
     io:println(c); // @output Infinity

     a = 0.0f;
     b = 0.0f;
     c = a * b;
     io:println(c); // @output 0.0

     a = -0.0f;
     b = 0.0f;
     c = a * b;
     io:println(c); // @output -0.0

     a = ();
     b = 0.0f;
     c = a * b;
     io:println(c.toBalString()); // @output ()

     a = -0.0f;
     b = ();
     c = a * b;
     io:println(c.toBalString()); // @output ()
}

Test-Case: output
Description: Test multiplication by NaN for different float values.
Labels: multiplicative-expr, numeric-literal, float-point-literal

public function main() {
     float a = 1321.32f;
     float b = float:NaN;
     float c = a * b;
     io:println(c); // @output NaN
     io:println(1321.32f * float:NaN); // @output NaN
     io:println(b * a); // @output NaN
     io:println(float:NaN * 1321.32f); // @output NaN

     a = float:NaN;
     b = float:NaN;
     c = a * b;
     io:println(c); // @output NaN
     io:println(a * b); // @output NaN

     a = float:Infinity;
     b = float:NaN;
     c = a * b;
     io:println(c); // @output NaN
     io:println(a * b); // @output NaN

     a = -float:Infinity;
     b = float:NaN;
     c = a * b;
     io:println(c); // @output NaN
     io:println(a * b); // @output NaN

     a = -0.0f;
     b = float:NaN;
     c = a * b;
     io:println(c); // @output NaN
     io:println(-0.0f * b); // @output NaN

     a = 0.0f;
     b = float:NaN;
     c = a * b;
     io:println(c); // @output NaN
     io:println(0.0f * b); // @output NaN
}

Test-Case: output
Description: Test multiplication by NaN for different nillable float values.
Labels: multiplicative-expr, numeric-literal, float-point-literal

public function main() {
     float? a = 1321.32f;
     float? b = float:NaN;
     float? c = a * b;
     io:println(c); // @output NaN

     a = float:NaN;
     b = float:NaN;
     c = a * b;
     io:println(c); // @output NaN

     a = float:Infinity;
     b = float:NaN;
     c = a * b;
     io:println(c); // @output NaN

     a = -float:Infinity;
     b = float:NaN;
     c = a * b;
     io:println(c); // @output NaN

     a = -0.0f
     b = float:NaN;
     c = a * b;
     io:println(c); // @output NaN

     a = 0.0f
     b = float:NaN;
     c = a * b;
     io:println(c); // @output NaN

     a = ();
     b = float:NaN;
     c = a * b;
     io:println(c.toBalString()); // @output ())
}

Test-Case: output
Description: Test multiplication by infinity for different float values.
Labels: multiplicative-expr, numeric-literal, float-point-literal

public function main() {
     float a = 1321.32f;
     float b = float:Infinity;
     float c = a * b;
     io:println(c); // @output Infinity
     io:println(1321.32f * float:Infinity); // @output Infinity
     io:println(b * a); // @output Infinity
     io:println(float:Infinity * 1321.32f); // @output Infinity

     a = float:Infinity;
     b = float:Infinity;
     c = a * b;
     io:println(c); // @output Infinity
     io:println(a * b); // @output Infinity

     a = float:Infinity;
     b = float:NaN;
     c = a * b;
     io:println(c); // @output NaN
     io:println(a * b); // @output NaN

     a = -float:Infinity;
     b = float:NaN;
     c = a * b;
     io:println(c); // @output NaN
     io:println(a * b); // @output NaN

     a = -0.0f
     b = float:Infinity;
     c = a * b;
     io:println(c); // @output NaN
     io:println(-0.0f * float:Infinity); // @output NaN

     a = 0.0f
     b = float:Infinity;
     c = a * b;
     io:println(c); // @output Infinity
     io:println(0.0f * float:Infinity); // @output NaN
}

Test-Case: output
Description: Test multiplication by infinity for different nillable float values.
Labels: multiplicative-expr, numeric-literal, float-point-literal

public function main() {
     float? a = 1321.32f;
     float? b = float:Infinity;
     float? c = a * b;
     io:println(c); // @output Infinity

     a = float:Infinity;
     b = float:Infinity;
     c = a * b;
     io:println(c); // @output Infinity

     a = float:Infinity;
     b = float:NaN;
     c = a * b;
     io:println(c); // @output NaN

     a = -float:Infinity;
     b = float:NaN;
     c = a * b;
     io:println(c); // @output NaN

     a = -0.0f
     b = float:Infinity;
     c = a * b;
     io:println(c); // @output NaN

     a = 0.0f
     b = float:Infinity;
     c = a * b;
     io:println(c); // @output Infinity

     a = ();
     b = float:Infinity;
     c = a * b;
     io:println(c.toBalString()); // @output ()


}

Test-Case: output
Description: Test division scenarios for different decimal values.
Labels: multiplicative-expr, numeric-literal, float-point-literal

public function main() {
     decimal a = 2.5E-17d;
     decimal b = 2.5E+17d;
     decimal c = b / a;
     io:println(c); // @output 1E+34
     io:println(2.5E+17d / 2.5E-17d); // @output 1E+34

     a = 1.423223E6d;
     b = 2.34413E2d;
     c = a / b;
     io:println(c); // @output 6071.433751541083472333019073174269
     io:println(1.423223E6d / 2.34413E2d); // @output 6071.433751541083472333019073174269

     a = 25.E1742d;
     b = 1.0d;
     c = a / b;
     io:println(c); // @output 2.5E+1743
     io:println(25.E1742d / 1.0d); // @output 2.5E+1743

     a = 25.E1742d;
     b = 0.0d;
     c = a / b;
     io:println(c); // @output Infinity
     io:println(25.E1742d / 0.0d); // @output Infinity

     a = 25.E17d;
     b = 0.9E-10d;
     c = a / b;
     io:println(c); // @output 27777777777777777777777777777.77778
     io:println(25.E17d / 0.9E-10d); // @output 27777777777777777777777777777.77778

     a = -25.E17d;
     b = 0.9E-10d;
     c = a / b;
     io:println(c); // @output -27777777777777777777777777777.77778
     io:println(-25.E17d / 0.9E-10d); // @output -27777777777777777777777777777.77778

     a = 17.E12d;
     b = 0.0d;
     c = a / b;
     io:println(c); // @output Infinity
     io:println(17.E12d / 0.0d); // @output Infinity

     a = -17.E12d;
     b = 0.0d;
     c = a / b;
     io:println(c); // @output -Infinity
     io:println(-17.E12d / 0.0d); // @output -Infinity

     a = 11.E12d;
     b = -0.0d;
     c = a / b;
     io:println(c); // @output Infinity
     io:println(11.E12d / -0.0d); // @output Infinity

     a = 17.E1290d;
     b = 13.E1521d;
     c = a / b;
     io:println(c); // @output 1.307692307692307692307692307692308E-231
     io:println(17.E1290d / 13.E1521d); // @output 1.307692307692307692307692307692308E-231

     a = 0.0d;
     b = 0.0d;
     c = a / b;
     io:println(c); // @output NaN
     io:println(0.0d / 0.0d); // @output NaN

     a = -0.0d;
     b = 0.0d;
     c = a / b;
     io:println(c); // @output NaN
     io:println(-0.0d / 0.0d); // @output NaN
}

Test-Case: output
Description: Test division scenarios for different nillable decimal values.
Labels: multiplicative-expr, numeric-literal, float-point-literal

public function main() {
     decimal? a = 2.5E-17d;
     decimal? b = 2.5E+17d;
     decimal? c = b / a;
     io:println(c); // @output 1E+34

     a = 1.423223E6d;
     b = 2.34413E2d;
     c = a / b;
     io:println(c); // @output 6071.433751541083472333019073174269

     a = 25.E1742d;
     b = 1.0d;
     c = a / b;
     io:println(c); // @output 2.5E+1743

     a = 25.E1742d;
     b = 0.0d;
     c = a / b;
     io:println(c); // @output Infinity

     a = 25.E17d;
     b = 0.9E-10d;
     c = a / b;
     io:println(c); // @output 27777777777777777777777777777.77778

     a = -25.E17d;
     b = 0.9E-10d;
     c = a / b;
     io:println(c); // @output -27777777777777777777777777777.77778

     a = 17.E12d;
     b = 0.0d;
     c = a / b;
     io:println(c); // @output Infinity

     a = -17.E12d;
     b = 0.0d;
     c = a / b;
     io:println(c); // @output -Infinity

     a = 11.E12d;
     b = -0.0d;
     c = a / b;
     io:println(c); // @output Infinity

     a = 17.E1290d;
     b = 13.E1521d;
     c = a / b;
     io:println(c); // @output 1.307692307692307692307692307692308E-231

     a = 0.0d;
     b = 0.0d;
     c = a / b;
     io:println(c); // @output NaN

     a = -0.0d;
     b = 0.0d;
     c = a / b;
     io:println(c); // @output NaN

     a = 17.E1290d;
     b = ();
     c = a / b;
     io:println(c.toBalString()); // @output ()

     a = ();
     b = 13.E1521d;
     c = a / b;
     io:println(c.toBalString()); // @output ()
}

Test-Case: output
Description: Test division scenarios for different float values.
Labels: multiplicative-expr, numeric-literal, float-point-literal

public function main() {
     float a = 2.5E-17;
     float b = 2.5E+17;
     float c = b / a;
     io:println(c); // @output 1.0000000000000001E34
     io:println(2.5E+17 / 2.5E-17); // @output 1.0000000000000001E34

     a = 1.423223E6;
     b = 2.34413E2;
     c = a / b;
     io:println(c); // @output 6071.433751541083
     io:println(1.423223E6 / 2.34413E2); // @output 6071.433751541083

     a = 25.E1742f;
     b = 1.0f;
     c = a / b;
     io:println(c); // @output Infinity
     io:println(25.E1742f / 1.0f); // @output Infinity

     a = 25.E1742f;
     b = 0.0f;
     c = a / b;
     io:println(c); // @output Infinity
     io:println(25.E1742f / 0.0f); // @output Infinity

     a = 25.E17f;
     b = 0.9E-10f;
     c = a / b;
     io:println(c); // @output 2.7777777777777776E28
     io:println(25.E17f / 0.9E-10); // @output 2.7777777777777776E28

     a = -25.E17f;
     b = 0.9E-10f;
     c = a / b;
     io:println(c); // @output -2.7777777777777776E28
     io:println(-25.E17f / 0.9E-10); // @output -2.7777777777777776E28

     a = 17.E12f;
     b = 0.0f;
     c = a / b;
     io:println(c); // @output Infinity
     io:println(17.E12f / 0.0f); // @output Infinity

     a = -17.E12f;
     b = 0.0f;
     c = a / b;
     io:println(c); // @output -Infinity
     io:println(-17.E12f / 0.0f); // @output -Infinity

     a = 11.E12f;
     b = -0.0f;
     c = a / b;
     io:println(c); // @output -Infinity
     io:println(11.E12f / -0.0f); // @output -Infinity

     a = 17.E1290f;
     b = 13.E1521f;
     c = a / b;
     io:println(c); // @output NaN
     io:println(17.E1290f / 13.E1521f); // @output NaN

     a = 0.0f;
     b = 0.0f;
     c = a / b;
     io:println(c); // @output NaN
     io:println(0.0f / 0.0f); // @output NaN

     a = -0.0f;
     b = 0.0f;
     c = a / b;
     io:println(c); // @output NaN
     io:println(-0.0f / 0.0f); // @output NaN
}

Test-Case: output
Description: Test division scenarios for different nillable float values.
Labels: multiplicative-expr, numeric-literal, float-point-literal

public function main() {
     float? a = 2.5E-17;
     float? b = 2.5E+17;
     float? c = b / a;
     io:println(c); // @output 1.0000000000000001E34

     a = 1.423223E6;
     b = 2.34413E2;
     c = a / b;
     io:println(c); // @output 6071.433751541083

     a = 25.E1742f;
     b = 1.0f;
     c = a / b;
     io:println(c); // @output Infinity

     a = 25.E1742f;
     b = 0.0f;
     c = a / b;
     io:println(c); // @output Infinity

     a = 25.E17f;
     b = 0.9E-10f;
     c = a / b;
     io:println(c); // @output 2.7777777777777776E28

     a = -25.E17f;
     b = 0.9E-10f;
     c = a / b;
     io:println(c); // @output -2.7777777777777776E28

     a = 17.E12f;
     b = 0.0f;
     c = a / b;
     io:println(c); // @output Infinity

     a = -17.E12f;
     b = 0.0f;
     c = a / b;
     io:println(c); // @output -Infinity

     a = 11.E12f;
     b = -0.0f;
     c = a / b;
     io:println(c); // @output -Infinity

     a = 17.E1290f;
     b = 13.E1521f;
     c = a / b;
     io:println(c); // @output NaN

     a = 0.0f;
     b = 0.0f;
     c = a / b;
     io:println(c); // @output NaN

     a = -0.0f;
     b = 0.0f;
     c = a / b;
     io:println(c); // @output NaN

     a = 11.E12f;
     b = ();
     c = a / b;
     io:println(c.toBalString()); // @output ()

     a = ();
     b = 13.E1521f;
     c = a / b;
     io:println(c.toBalString()); // @output ()
}

Test-Case: output
Description: Test division by infinity for different float values.
Labels: multiplicative-expr, numeric-literal, float-point-literal

public function main() {

     float a = float:Infinity;
     float b = float:Infinity;
     float c = a / b;
     io:println(c); // @output NaN
     io:println(float:Infinity / float:Infinity); // @output NaN

     a = 14.34f;
     b = float:Infinity;
     c = a / b;
     io:println(c); // @output 0.0
     io:println(14.34f / float:Infinity); // @output 0.0

     a = 14.34f;
     b = -float:Infinity;
     c = a / b;
     io:println(c); // @output -0.0
     io:println(14.34f / -float:Infinity); // @output -0.0

     a = float:NaN;
     b = float:Infinity;
     c = a / b;
     io:println(c); // @output NaN
     io:println(float:NaN / float:Infinity); // @output NaN

     a = float:NaN;
     b = -float:Infinity;
     c = a / b;
     io:println(c); // @output NaN
     io:println(float:NaN / -float:Infinity); // @output NaN
}

Test-Case: output
Description: Test division by infinity for different nillable float values.
Labels: multiplicative-expr, numeric-literal, float-point-literal

public function main() {

     float? a = float:Infinity;
     float? b = float:Infinity;
     float? c = a / b;
     io:println(c); // @output NaN

     a = 14.34f;
     b = float:Infinity;
     c = a / b;
     io:println(c); // @output 0.0

     a = 14.34f;
     b = -float:Infinity;
     c = a / b;
     io:println(c); // @output -0.0

     a = float:NaN;
     b = float:Infinity;
     c = a / b;
     io:println(c); // @output NaN

     a = float:NaN;
     b = -float:Infinity;
     c = a / b;
     io:println(c); // @output NaN

     a = ();
     b = -float:Infinity;
     c = a / b;
     io:println(c.toBalString()); // @output ()
}

Test-Case: output
Description: Test division by NaN for different float values.
Labels: multiplicative-expr, numeric-literal, float-point-literal

public function main() {
     float a = 1321.32f;
     float b = float:NaN;
     float c = a / b;
     io:println(c); // @output NaN
     io:println(1321.32f / float:NaN); // @output NaN
     io:println(b / a); // @output NaN
     io:println(float:NaN / 1321.32f); // @output NaN

     a = float:NaN;
     b = float:NaN;
     c = a / b;
     io:println(c); // @output NaN
     io:println(a / b); // @output NaN

     a = float:Infinity;
     b = float:NaN;
     c = a / b;
     io:println(c); // @output NaN
     io:println(a / b); // @output NaN

     a = -float:Infinity;
     b = float:NaN;
     c = a / b;
     io:println(c); // @output NaN
     io:println(a / b); // @output NaN
}

Test-Case: output
Description: Test division by NaN for different nillable float values.
Labels: multiplicative-expr, numeric-literal, float-point-literal

public function main() {
     float? a = 1321.32f;
     float? b = float:NaN;
     float? c = a / b;
     io:println(c); // @output NaN

     a = float:NaN;
     b = float:NaN;
     c = a / b;
     io:println(c); // @output NaN

     a = float:Infinity;
     b = float:NaN;
     c = a / b;
     io:println(c); // @output NaN

     a = -float:Infinity;
     b = float:NaN;
     c = a / b;
     io:println(c); // @output NaN

     a = ();
     b = float:NaN;
     c = a / b;
     io:println(c.toBalString()); // @output ()
}

Test-Case: output
Description: Test remainder operation for different float values.
Labels: multiplicative-expr, numeric-literal, float-point-literal

public function mainx() {
     float a = float:NaN;
     float b = 2.5E+17;
     float c = b % a;
     io:println(c); // @output NaN
     io:println(2.5E+17 % float:NaN); // @output NaN

     a = 1.423223E6;
     b = float:NaN;
     c = a % b;
     io:println(c); // @output NaN
     io:println(1.423223E6 % float:NaN); // @output NaN

     a = float:Infinity;
     b = 1.423223E6;
     c = a % b;
     io:println(c); // @output NaN
     io:println(float:Infinity % 1.423223E6); // @output NaN

     a = 25.E1742f;
     b = 0.0f;
     c = a % b;
     io:println(c); // @output NaN
     io:println(25.E1742f % 0.0f); // @output NaN

     a = 25.E17f;
     b = float:Infinity;
     c = a % b;
     io:println(c); // @output 2.5E18
     io:println(25.E17f % float:Infinity); // @output 2.5E18

     a = 25.E17f;
     b = 25.E17f;
     c = a % b;
     io:println(c); // @output 0
     io:println(25.E17f % 25.E17f); // @output 0

     a = -25.E17f;
     b = 25.E17f;
     c = a % b;
     io:println(c); // @output -0.0
     io:println(-25.E17f % 25.E17f); // @output -0.0

     a = 25.E17f;
     b = -25.E17f;
     c = a % b;
     io:println(c); // @output 0.0
     io:println(25.E17f % -25.E17f); // @output 0.0

     a = 25.78f;
     b = -5.34f;
     c = a % b;
     io:println(c); // @output 4.420000000000002
     io:println(25.78f % -5.34f); // @output 4.420000000000002

     a = -25.78f;
     b = 5.34f;
     c = a % b;
     io:println(c); // @output -4.420000000000002
     io:println(-25.78f % 5.34f); // @output -4.420000000000002

     a = 0.0f;
     b = 0.0f;
     c = a % b;
     io:println(c); // @output NaN
     io:println(0.0f % 0.0f); // @output NaN

     a = -0.0f;
     b = 0.0f;
     c = a % b;
     io:println(c); // @output NaN
     io:println(-0.0f % 0.0f); // @output NaN
}

Test-Case: output
Description: Test remainder operation for different nillable float values.
Labels: multiplicative-expr, numeric-literal, float-point-literal

public function mainx() {
     float? a = float:NaN;
     float? b = 2.5E+17;
     float? c = b % a;
     io:println(c); // @output NaN

     a = 1.423223E6;
     b = float:NaN;
     c = a % b;
     io:println(c); // @output NaN

     a = float:Infinity;
     b = 1.423223E6;
     c = a % b;
     io:println(c); // @output NaN

     a = 25.E1742f;
     b = 0.0f;
     c = a % b;
     io:println(c); // @output NaN

     a = 25.E17f;
     b = float:Infinity;
     c = a % b;
     io:println(c); // @output 2.5E18

     a = 25.E17f;
     b = 25.E17f;
     c = a % b;
     io:println(c); // @output 0

     a = -25.E17f;
     b = 25.E17f;
     c = a % b;
     io:println(c); // @output -0.0

     a = 25.E17f;
     b = -25.E17f;
     c = a % b;
     io:println(c); // @output 0.0

     a = 25.78f;
     b = -5.34f;
     c = a % b;
     io:println(c); // @output 4.420000000000002

     a = -25.78f;
     b = 5.34f;
     c = a % b;
     io:println(c); // @output -4.420000000000002

     a = 0.0f;
     b = 0.0f;
     c = a % b;
     io:println(c); // @output NaN

     a = -0.0f;
     b = 0.0f;
     c = a % b;
     io:println(c); // @output NaN

     a = 25.78f;
     b = ();
     c = a % b;
     io:println(c.toBalString()); // @output ()

     a = ();
     b = 5.34f;
     c = a % b;
     io:println(c.toBalString()); // @output ()
}

Test-Case: output
Description: Test remainder operation for different decimal values.
Labels: multiplicative-expr, numeric-literal, float-point-literal

public function main() {
     decimal a = 25.E1742d;
     decimal b = 0.0d;
     decimal c = a % b;
     io:println(c); // @output NaN
     io:println(25.E1742d % 0.0d); // @output NaN

     a = 25.E17d;
     b = 25.E8632d;
     c = a % b;
     io:println(c); // @output 2.5E18
     io:println(25.E17d % 25.E8632d); // @output 2.5E18

     a = 25.E17d;
     b = 25.E17d;
     c = a % b;
     io:println(c); // @output 0
     io:println(25.E17d % 25.E17d); // @output 0

     a = -25.1E17d;
     b = 25.1E17d;
     c = a % b;
     io:println(c); // @output 0
     io:println(-25.1E17d % 25.1E17d); // @output 0

     a = 25.E17d;
     b = -25.E17d;
     c = a % b;
     io:println(c); // @output 0.0
     io:println(25.E17d % -25.E17d); // @output 0.0

     a = 25.78d;
     b = -5.34d;
     c = a % b;
     io:println(c); // @output 4.42
     io:println(25.78d % -5.34d); // @output 4.42

     a = -25.78d;
     b = 5.34d;
     c = a % b;
     io:println(c); // @output -4.42
     io:println(-25.78d % 5.34d); // @output -4.42

     a = 0.0d;
     b = 0.0d;
     c = a % b;
     io:println(c); // @output NaN
     io:println(0.0d % 0.0d); // @output NaN

     a = -0.0d;
     b = 0.0d;
     c = a % b;
     io:println(c); // @output NaN
     io:println(-0.0d % 0.0d); // @output NaN
}

Test-Case: output
Description: Test remainder operation for different nillable decimal values.
Labels: multiplicative-expr, numeric-literal, float-point-literal

public function main() {
     decimal? a = 25.E1742d;
     decimal? b = 0.0d;
     decimal? c = a % b;
     io:println(c); // @output NaN

     a = 25.E17d;
     b = 25.E8632d;
     c = a % b;
     io:println(c); // @output 2.5E18

     a = 25.E17d;
     b = 25.E17d;
     c = a % b;
     io:println(c); // @output 0

     a = -25.1E17d;
     b = 25.1E17d;
     c = a % b;
     io:println(c); // @output 0

     a = 25.E17d;
     b = -25.E17d;
     c = a % b;
     io:println(c); // @output 0.0

     a = 25.78d;
     b = -5.34d;
     c = a % b;
     io:println(c); // @output 4.42

     a = -25.78d;
     b = 5.34d;
     c = a % b;
     io:println(c); // @output -4.42

     a = 0.0d;
     b = 0.0d;
     c = a % b;
     io:println(c); // @output NaN

     a = -0.0d;
     b = 0.0d;
     c = a % b;
     io:println(c); // @output NaN

     a = 25.78d;
     b = ();
     c = a % b;
     io:println(c.toBalString()); // @output ()

     a = ();
     b = 5.34d;
     c = a % b;
     io:println(c.toBalString()); // @output ()
}

Test-Case: output
Description: Test float multiplication scenarios for user-defined subtypes of float.
Labels: multiplicative-expr, numeric-literal, float-literal, module-type-defn

type Floats -2.0f|-1.0f|0.0f|1.0f|2.0f;

public function main() {
    Floats a = 1.0;
    Floats b = 2.0;
    float c = a * a;

    float d = a * b;

    io:println(c); // @output 1.0
    io:println(a * a); // @output 1.0
    io:println(d); //@output 2.0
    io:println(a * b); // @output 2.0

    io:println(b * a); // @output 2.0
    io:println(b * b); // @output 4.0
}

Test-Case: output
Description: Test decimal multiplication scenarios for user-defined subtypes of decimal.
Labels: multiplicative-expr, numeric-literal, decimal-literal, module-type-defn

type Decimals -2.0d|-1.0d|0.0d|1.0d|2.0d;

public function main() {
    Decimals a = 1.0d;
    Decimals b = 2.0d;
    decimal c = a * a;
    decimal d = a * b;

    io:println(a * a); // @output 1.0
    io:println(c); // @output 1.0
    io:println(a * b); // @output 2.0
    io:println(d); // @output 2.0

    io:println(b * a); // @output 2.0
    io:println(b * b); // @output 4.0
}

Test-Case: output
Description: Test float division scenarios for user-defined subtypes of float.
Labels: multiplicative-expr, numeric-literal, float-literal, module-type-defn

type Floats -2.0f|-1.0f|0.0f|1.0f|2.0f;

public function main() {
    Floats a = 1.0;
    Floats b = 2.0;
    float c = a / a;
    float d = a / b;

    io:println(c); // @output 1.0
    io:println(a / a); // @output 1.0
    io:println(d); //@output 0.5
    io:println(a / b); // @output 0.5

    io:println(b / a); // @output 2.0
    io:println(b / b); // @output 1.0

    a = -0.0;
    b = +0.0;
    Floats e = 2.0f;
    io:println(e / a); // @output -Infinity
    io:println(e / b); // @output Infinity
}

Test-Case: output
Description: Test decimal division scenarios for user-defined subtypes of decimal.
Labels: multiplicative-expr, numeric-literal, decimal-literal, module-type-defn

type Decimals -2.0d|-1.0d|0.0d|1.0d|2.0d;

public function main() {
    Decimals a = 1.0d;
    Decimals b = 2.0d;
    decimal c = a / a;
    decimal d = a / b;

    io:println(a / a); // @output 1.0
    io:println(c); // @output 1.0
    io:println(a / b); // @output 0.5
    io:println(d); // @output 0.5

    io:println(b / a); // @output 2.0
    io:println(b / b); // @output 1.0
}

Test-Case: output
Description: Test remainder operation for user-defined subtypes of float.
Labels: multiplicative-expr, numeric-literal, float-literal, module-type-defn

type Floats -2.0f|-1.0f|0.0f|1.0f|2.0f|-0.0f;

public function main() {
    Floats a = 1.0;
    Floats b = 2.0;
    float c = a % a;

    float d = a % b;

    io:println(c); // @output 0.0
    io:println(a % a); // @output 0.0
    io:println(d); //@output 1.0
    io:println(a % b); // @output 1.0

    io:println(b % a); // @output 0.0
    io:println(b % b); // @output 0.0
}

Test-Case: output
Description: Test remainder operation for user-defined subtypes of decimal.
Labels: multiplicative-expr, numeric-literal, decimal-literal, module-type-defn

type Decimals -2.0d|-1.0d|0.0d|1.0d|2.0d;

public function main() {
    Decimals a = 1.0d;
    Decimals b = 2.0d;
    decimal c = a % a;
    decimal d = a % b;

    io:println(a % a); // @output 0.0
    io:println(c); // @output 0.0
    io:println(a % b); // @output 1.0
    io:println(d); // @output 1.0

    io:println(b % a); // @output 0.0
    io:println(b % b); // @output 0.0
}

Test-Case: error
Description: Test the static type of the result being the basic type of the operands via invalid assignment,
             where operands are of types that are user-defined subtypes of float types.
Labels: multiplicative-expr, float-type-descriptor, numeric-literal, float-literal

type Floats 1f|2f;

public function main(float a, float b, Floats c) {
    Floats f1  = a * b; // @error static type of multiplicative-expr with operands of float subtypes is float
    Floats f2 = a / b; // @error static type of multiplicative-expr with operands of float subtypes is float
    Floats f3 = a % b; // @error static type of multiplicative-expr with operands of float subtypes is float
}

Test-Case: error
Description: Test the static type of the result being the basic type of the operands via invalid assignment,
             where operands are of types that are user-defined subtypes of float types.
Labels: multiplicative-expr, float-type-descriptor, numeric-literal, float-literal

type Floats 1f|2f;

public function main(float a, float b, Floats c) {
    Floats f1  = a * b; // @error static type of multiplicative-expr with operands of float subtypes is float
    Floats f2 = a / b; // @error static type of multiplicative-expr with operands of float subtypes is float
    Floats f3 = a % b; // @error static type of multiplicative-expr with operands of float subtypes is float
}

Test-Case: error
Description: Test the static type of the result being the basic type of the operands via invalid assignment,
             where operands are of types that are user-defined subtypes of decimal types.
Labels: multiplicative-expr, decimal-type-descriptor, numeric-literal, decimal-literal

type Decimals 1d|2d;

public function main(decimal a, decimal b, Decimals c) {
    Decimals f1  = a * b; // @error static type of multiplicative-expr with operands of decimal subtypes is decimal
    Decimals f2 = a / b; // @error static type of multiplicative-expr with operands of decimal subtypes is decimal
    Decimals f3 = a % b; // @error static type of multiplicative-expr with operands of decimal subtypes is decimal
}