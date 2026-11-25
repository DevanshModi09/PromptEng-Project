"""CampusCrew matching algorithm + simulation (sample profiles, clearly synthetic)."""
import random, statistics as st
ROLES = ["Frontend", "Backend", "ML/AI", "UI/UX Design", "Pitch/Presentation", "Research/Domain"]
CORE = {"Frontend", "Backend", "UI/UX Design", "Pitch/Presentation"}
INTERESTS = ["HealthTech", "EdTech", "FinTech", "AgriTech", "Sustainability", "Smart Campus"]
# assumed skew: many web devs, few designers/pitchers (typical in CSE batches)
ROLE_WEIGHTS = [30, 25, 20, 8, 7, 10]

def make_students(n, seed):
    rnd = random.Random(seed); out = []
    for i in range(n):
        primary = rnd.choices(ROLES, ROLE_WEIGHTS)[0]
        skills = {primary}
        if rnd.random() < 0.4: skills.add(rnd.choices(ROLES, ROLE_WEIGHTS)[0])
        out.append(dict(id=f"S{i+1:02d}", skills=skills, interests=set(rnd.sample(INTERESTS, 2)),
                        slots=set(rnd.sample(range(7), 3)), rating=round(rnd.uniform(3, 5), 1)))
    return out

def jaccard(a, b): return len(a & b) / len(a | b) if a | b else 0

def match_score(team, c):
    covered = set().union(*(m["skills"] for m in team))
    new_roles = len(c["skills"] - covered) / len(c["skills"])          # complementarity
    interest = st.mean(jaccard(c["interests"], m["interests"]) for m in team)
    avail = st.mean(jaccard(c["slots"], m["slots"]) for m in team)
    return 0.40 * new_roles + 0.25 * interest + 0.20 * avail + 0.15 * (c["rating"] / 5)

def build_teams(students, size):
    """1) spread the rarest core roles across teams, 2) fill the rest by match score."""
    teams = [[] for _ in range(len(students) // size)]
    pool = students[:]
    count = {r: sum(r in s["skills"] for s in pool) for r in CORE}
    for role in sorted(CORE, key=lambda r: count[r]):                 # rarest role first
        for t in teams:
            if any(role in m["skills"] for m in t):
                continue
            cands = [s for s in pool if role in s["skills"]]
            if not cands:
                break
            best = max(cands, key=lambda c: match_score(t, c) if t else c["rating"])
            t.append(best); pool.remove(best)
    for t in teams:
        while len(t) < size and pool:
            best = max(pool, key=lambda c: match_score(t, c) if t else c["rating"])
            t.append(best); pool.remove(best)
    return teams

def random_teams(students, size, seed):                               # baseline: like friend groups
    s = students[:]; random.Random(seed).shuffle(s)
    return [s[i:i+size] for i in range(0, len(s) - size + 1, size)]

def evaluate(teams):
    cov = [len(set().union(*(m["skills"] for m in t))) for t in teams]
    core = [CORE <= set().union(*(m["skills"] for m in t)) for t in teams]
    return st.mean(cov), 100 * sum(core) / len(core)

if __name__ == "__main__":
    R, H = [], []
    for seed in range(20):                                              # 20 runs x 60 students, teams of 6
        S = make_students(60, seed)
        R.append(evaluate(random_teams(S, 6, seed))); H.append(evaluate(build_teams(S, 6)))
    print("RANDOM  avg roles/team %.2f  core-complete %.1f%%" % (st.mean(r[0] for r in R), st.mean(r[1] for r in R)))
    print("CAMPUSCREW avg roles/team %.2f  core-complete %.1f%%" % (st.mean(h[0] for h in H), st.mean(h[1] for h in H)))
    S = make_students(60, 7)
    for t in build_teams(S, 6)[:2]:
        print([ (m["id"], "/".join(sorted(m["skills"]))) for m in t])
    t = build_teams(S, 6)[0][:3]; cands = sorted([c for c in S if c not in t], key=lambda c: -match_score(t, c))[:4]
    print("team so far:", [(m["id"], "/".join(m["skills"])) for m in t])
    for c in cands: print(c["id"], "/".join(sorted(c["skills"])), sorted(c["interests"]), c["rating"], round(match_score(t, c), 2))
