<<<<<<< HEAD
local GuideData = {
  categories = {
    {
      id = "getting_started",
      title = "Getting Started",
      articles = {
        {
          id = "welcome",
          title = "Welcome",
          summary = "Your path from a tiny stand to a full business.",
          body = [[
Goal: grow from a small stand into a full business.

Watch the top bar for Time, Stage, Money, Level, and XP.
Use the Main Page for guides, stats, and snapshots.
Progress by crafting products, serving customers, and buying upgrades.
          ]]
        }
      }
    },
    {
      id = "stocks",
      title = "Stocks",
      articles = {
        {
          id    = "stock_basics",
          title = "How Stock Works",
          summary = "where you get materials.",
          body = [[
- Materials (cups, fruit, sweeteners, toppings) are consumed to craft products (check craft guide). Each day at 6am the stock of items are reset and, Each week the prices of items change.
- each item type has a rarity scale.
- The rarity scale is : common: gray | uncommon: light gray | rare: green | unique: blue | legendary: yellow | mythical: orange | relic: purple | masterwork: magenta | divine: pink |
- Depending on the rarity will give a better output on the price(check inv for the base price of item)
- The more rare an item is the more exp you get when its used.
        ]]
        },
      }
    },
        {
      id = "crafting",
      title = "Crafting",
      articles = {
        {
          id    = "craft_basics",
          title = "How Crafting Works",
          summary = "Materials -> Products. Keep materials above demand.",
          body = [[
- Materials (cups, fruit, ice, sugar) are consumed to craft products.
- Some upgrades reduce material requirements (e.g., Juicer).
- Keep materials above expected demand to avoid stockouts.

Quick math:
- Each ingredient shows rq:x (required units).
- If Juicer is owned, fruit rq goes down by 1 for Lemonade.
- Be sure to keep in mind of the rq:# and S:# when crafting. The rq is required amount, and S: is your current stock amount.
          ]]
        },
      }
    },
    {
      id = "selling",
      title = "Selling & Customers",
      articles = {
        {
          id = "sales_loop",
          title = "Selling & Customers",
          summary = "Customers arrive over time; keep stock ready.",
          body = [[
- When Open for Business, customers arrive over time, these hours are between 7am to 7pm.
- Buy chance depends on availability, variety, and reputation.
- Upgrades also can affect your sales probability.(check out the upgrades guide)
- If stock runs out, sales pause until you craft more.
          ]]
        }
      }
    },
        {
      id = "licenses",
      title = "Licenses Usage",
      articles = {
        {
          id = "license",
          title = "The Usage of License",
          summary = "Required in order to reach the next stage",
          body = [[
- Buying a License is only used for gaining access to the next property to manage.
- It unlocks the capability to buy the property.
- The list of license are: business : commercial : manufacturing : High-Rise : which are required for building the next property.
          ]]
        }
      }
    },
        {
      id = "upgrades",
      title = "Upgrading",
      articles = {
        {
          id = "upgrade",
          title = "The Benefits of upgrades.",
          summary = "Each upgrade helps progress faster.",
          body = [[
- Each upgrade helps the business grow and gain more in the end.
- When upgrading keep in mind your budget, upgrades can get expensive.
- marketing is a great way to increase the number of customers you get.
- Seating can help with getting a successful purchase, while an awning might encourage customers to buy a higher priced item.
- Key upgrades like: Juicer or Ice shaver can help in other ways. Juicer helps reduce the fruit requirement for any heavy focused drink products.
- Ice Shaver allows you to create a new product that can help with more sales.
          ]]
        }
      }
    },
    
  }
}

=======
local GuideData = {
  categories = {
    {
      id = "getting_started",
      title = "Getting Started",
      articles = {
        {
          id = "welcome",
          title = "Welcome",
          summary = "Your path from a tiny stand to a full business.",
          body = [[
Goal: grow from a small stand into a full business.

Watch the top bar for Time, Stage, Money, Level, and XP.
Use the Main Page for guides, stats, and snapshots.
Progress by crafting products, serving customers, and buying upgrades.
          ]]
        }
      }
    },
    {
      id = "stocks",
      title = "Stocks",
      articles = {
        {
          id    = "stock_basics",
          title = "How Stock Works",
          summary = "where you get materials.",
          body = [[
- Materials (cups, fruit, sweeteners, toppings) are consumed to craft products (check craft guide). Each day at 6am the stock of items are reset and, Each week the prices of items change.
- each item type has a rarity scale.
- The rarity scale is : common: gray | uncommon: light gray | rare: green | unique: blue | legendary: yellow | mythical: orange | relic: purple | masterwork: magenta | divine: pink |
- Depending on the rarity will give a better output on the price(check inv for the base price of item)
- The more rare an item is the more exp you get when its used.
        ]]
        },
      }
    },
        {
      id = "crafting",
      title = "Crafting",
      articles = {
        {
          id    = "craft_basics",
          title = "How Crafting Works",
          summary = "Materials -> Products. Keep materials above demand.",
          body = [[
- Materials (cups, fruit, ice, sugar) are consumed to craft products.
- Some upgrades reduce material requirements (e.g., Juicer).
- Keep materials above expected demand to avoid stockouts.

Quick math:
- Each ingredient shows rq:x (required units).
- If Juicer is owned, fruit rq goes down by 1 for Lemonade.
- Be sure to keep in mind of the rq:# and S:# when crafting. The rq is required amount, and S: is your current stock amount.
          ]]
        },
      }
    },
    {
      id = "selling",
      title = "Selling & Customers",
      articles = {
        {
          id = "sales_loop",
          title = "Selling & Customers",
          summary = "Customers arrive over time; keep stock ready.",
          body = [[
- When Open for Business, customers arrive over time, these hours are between 7am to 7pm.
- Buy chance depends on availability, variety, and reputation.
- Upgrades also can affect your sales probability.(check out the upgrades guide)
- If stock runs out, sales pause until you craft more.
          ]]
        }
      }
    },
        {
      id = "licenses",
      title = "Licenses Usage",
      articles = {
        {
          id = "license",
          title = "The Usage of License",
          summary = "Required in order to reach the next stage",
          body = [[
- Buying a License is only used for gaining access to the next property to manage.
- It unlocks the capability to buy the property.
- The list of license are: business : commercial : manufacturing : High-Rise : which are required for building the next property.
          ]]
        }
      }
    },
        {
      id = "upgrades",
      title = "Upgrading",
      articles = {
        {
          id = "upgrade",
          title = "The Benefits of upgrades.",
          summary = "Each upgrade helps progress faster.",
          body = [[
- Each upgrade helps the business grow and gain more in the end.
- When upgrading keep in mind your budget, upgrades can get expensive.
- marketing is a great way to increase the number of customers you get.
- Seating can help with getting a successful purchase, while an awning might encourage customers to buy a higher priced item.
- Key upgrades like: Juicer or Ice shaver can help in other ways. Juicer helps reduce the fruit requirement for any heavy focused drink products.
- Ice Shaver allows you to create a new product that can help with more sales.
          ]]
        }
      }
    },
    
  }
}

>>>>>>> 52c40b5160b49a22fadef8e888dcdd0a911ebadf
return GuideData