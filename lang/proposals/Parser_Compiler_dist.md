This is a high-level overview and casual description of the proposed functionality;

Historical Perspective:

1. CSS, or Cascading Style Sheets, behave in the reverse of the manner desired in this proposal. CSS files are seperately created during development
and can be scoped quite easily. When they are loaded though, they behave as a single file. Hence the name.

2. Microsoft's DirectX line still reminds me of almost infinite amounts of .dll files, or what they refer to as Dynamic Link Libraries.

3. Angular and Vue allow us to import/export from anywhere, and file structure can be made neglible.

1+2+3:

Desired behaviour for .bal:

Would it be possible to combine all the individual .bal files per module into a single .bal file during development, and then at build-time
would it be possible for the compiler to break the monolithic .bal file into as many as possible, smaller .bal files?

Reasoning w.r.t Possible/Percieved Performance Gains:

The underlying assumptions are that the speed of the "ls" and "cd" commands/operations are equivalent, with bias in favour of "cd".
The other assumption, is that it is harder for a malicious agent to compromise a system if it has a very complicated directory/file structure.
Also, that systems with expansive directory/file structures are more robust in that they fail incrementally.

So basically I want to be able to copy paste like crazy into ONE FILE so that I dont have to navigate my app whilst building it.
I also want the build command to then chop up all my code, super fast like it's eating a video stream, and then produce like 1000
random .bal files. And I'm just thinking this should be quite possible and easy to implement. I want this because I don't like having
all my import statements in one place, and I hate having .json and .yaml and .toml and .gulp files telling everyone and everything exactly
whats going on and where is what. Security through Obscurity.

(aaand it should be like SUPER SUPER SUPER FAST)
