# First instructions for your coding agent

## Before you start (your checklist)
1. Make a folder for the project, for example `nearby`.
2. Put `PROJECT.md` and `nearby-classifieds.html` in that folder.
3. Create a free Supabase project (supabase.com). In its settings, find the **Project URL** and the **anon public key**. You'll give those to the agent. Do **not** share the `service_role` key with anyone or put it in any file.
4. Create a GitHub account and an empty repository to store your work.
5. Open your AI coding agent in the project folder.

## Prompt 0: get oriented (paste this first)
```
Read PROJECT.md and nearby-classifieds.html in this folder. Then:
1. Summarize in plain language what the prototype does and what we're building.
2. Tell me which Phase 1 steps you plan to do, in order, and what you'll need from me.
3. Set up Git in this folder with a sensible .gitignore, and make a first commit.
Don't change any code yet. Remember I know HTML and classic ASP but haven't coded in over ten years, so explain things simply.
```

## Prompt 1: the database
```
Phase 1, step 1 only. Using the data model in PROJECT.md, write the SQL to create the tables for profiles, categories, cities, listings, listing_photos, and favorites. Put it in a file called schema.sql. Include row-level security policies that follow the security rules in PROJECT.md, and seed the categories and cities from the prototype's lists. Explain each policy in plain language. Don't touch the website yet. Tell me exactly how to run the SQL in Supabase and how to check it worked.
```

## Prompt 2: connect the page and add login
```
Phase 1, step 2 only. Create a small config.js that holds the public Supabase URL and anon key (I'll paste the values in myself). Copy the prototype into index.html and connect it to Supabase. Add sign up, log in, and log out, with a simple, clear design that matches the prototype. Keep everything else as is. Tell me how to test it and what each new piece of code does.
```

## Prompt 3: load real listings
```
Phase 1, step 3 only. Replace the in-memory sample data with real data from Supabase: categories, cities, and listings. Add demo listings (is_demo = true) taken from the prototype's sample ads so the site isn't empty. Keep search, sorting, the city and radius filter, and the Saved view working. Do the radius filtering in the browser for now. Explain what changed.
```

## Prompt 4: post an ad with photos
```
Phase 1, step 4 only. Make the Post an ad form save to the database, with photo upload to Supabase Storage. Only signed-in users can post. Limit photo type and size, and limit how many ads one account can post per day. Add edit and delete for my own ads only. Test that another account can't change my ads, and show me how I can check that myself.
```

## Prompt 5: saved ads per account
```
Phase 1, step 5 only. Make the heart/Save button store favorites in the database for the signed-in user, and show them in the Saved view. Favorites must be private to each user.
```

## Prompt 6: put it online
```
Phase 1, step 6 only. Help me publish this site on Netlify (or Vercel), connected to my GitHub repository. Walk me through it step by step. Double-check that no secret keys are in any published file, and update NOTES.md with what's done and what's next.
```

## After each step
- Open the site and test the thing the agent just built, including on your phone.
- Ask: "What could go wrong with this change? Is anything here a security risk?"
- Make sure the agent has committed the change before you move on.

## Tips
- If the agent starts doing several things at once, say: "Stop. One step at a time, as PROJECT.md says."
- If something breaks, paste the exact error message and say what you did just before it.
- When Phase 1 is done, come back and I'll help you write the Phase 2 prompts.
