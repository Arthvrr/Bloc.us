import streamlit as st
import json
import os
from datetime import datetime
import calendar
import pandas as pd
import plotly.express as px

st.set_page_config(page_title="Bloc.us", layout="wide")
st.title("📚 Bloc.us - Ton partenaire de blocus")

# -------------------------
# INIT & AUTO-SAVE
# -------------------------
DB_FILE = "blocus_data.json"

if "loaded" not in st.session_state:
    if os.path.exists(DB_FILE):
        with open(DB_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
            st.session_state.courses = data.get("courses", {})
            st.session_state.schedule = data.get("schedule", {})
    else:
        st.session_state.courses = {}
        st.session_state.schedule = {}
    st.session_state.loaded = True

def auto_save():
    with open(DB_FILE, "w", encoding="utf-8") as f:
        json.dump({
            "courses": st.session_state.courses,
            "schedule": st.session_state.schedule
        }, f, indent=2)

# -------------------------
# UTILITAIRES
# -------------------------
def compute_progress(tasks):
    total_done = sum(t["done"] for t in tasks)
    total_possible = sum(t["total"] for t in tasks)
    return total_done / total_possible if total_possible else 0

def compute_exam_needed(grading):
    total_points = sum(g["total"] for g in grading)
    earned_points = sum(g["score"] for g in grading)
    exam_total = max(0, 20 - total_points)
    needed_exam = 10 - earned_points
    return round(exam_total, 2), round(max(0, needed_exam), 2)

def progress_bar(progress, color):
    st.markdown(f"""
    <div style="background:#eaeaea;border-radius:10px;height:18px;margin-bottom:5px;">
        <div style="
            background:{color};
            width:{progress*100}%;
            height:100%;
            border-radius:10px;
            transition:0.3s;
        "></div>
    </div>
    <div style="font-size:12px;color:gray;margin-bottom:10px;">
        {round(progress*100, 2)}% accompli
    </div>
    """, unsafe_allow_html=True)

# -------------------------
# SIDEBAR
# -------------------------
st.sidebar.header("⚙️ Gestion des cours")

new_course = st.sidebar.text_input("Nom du cours")
color = st.sidebar.color_picker("Couleur", "#4CAF50")

if st.sidebar.button("Ajouter le cours"):
    if new_course and new_course not in st.session_state.courses:
        st.session_state.courses[new_course] = {
            "tasks": [],
            "color": color,
            "grading": []
        }
        auto_save()
        st.rerun()

if st.session_state.courses:
    c = st.sidebar.selectbox("Supprimer un cours", list(st.session_state.courses.keys()))
    if st.sidebar.button("❌ Supprimer"):
        del st.session_state.courses[c]
        auto_save()
        st.rerun()

# -------------------------
# CALCULS GLOBAUX
# -------------------------
courses = list(st.session_state.courses.keys())
today_str = datetime.today().strftime("%Y-%m-%d")

study_days_count = {c: {"total": 0, "remaining": 0} for c in courses}

for date_str, events in st.session_state.schedule.items():
    for e in events:
        if e["type"] == "Étude" and e["course"] in study_days_count:
            study_days_count[e["course"]]["total"] += 1
            if date_str >= today_str:
                study_days_count[e["course"]]["remaining"] += 1

# -------------------------
# TABS
# -------------------------
tabs = ["📊 Général", "📅 Planning"] + courses
tab_objs = st.tabs(tabs)

# -------------------------
# 1. GENERAL
# -------------------------
with tab_objs[0]:
    # --- 1. FOCUS DU JOUR (Tout en haut) ---
    st.header("🎯 Focus du jour")
    
    todays_events = st.session_state.schedule.get(today_str, [])
    
    if todays_events:
        for ev in todays_events:
            c = ev["course"]
            if c not in st.session_state.courses: continue
            
            if ev["type"] == "Examen":
                st.error(f"### 🚨 EXAMEN AUJOURD'HUI : {c}\nBon courage, donne tout !!")
                if ev.get("description"):
                    st.write(f"📝 **Détails :** {ev['description']}")
            else:
                study_dates = [d for d, evs in st.session_state.schedule.items() for e in evs if e["course"] == c and e["type"] == "Étude"]
                study_dates.sort()
                
                try:
                    nth_day = study_dates.index(today_str) + 1
                except ValueError:
                    nth_day = 1
                    
                total_days = len(study_dates)
                prog = compute_progress(st.session_state.courses[c]["tasks"])
                col_color = st.session_state.courses[c]["color"]
                
                with st.container(border=True):
                    st.markdown(f"#### 📚 {c} — *Jour {nth_day} sur {total_days}*")
                    if ev.get("description"):
                        st.markdown(f"**🎯 Objectif :** {ev['description']}")
                    progress_bar(prog, col_color)
    else:
        st.success("🎉 Rien de prévu au calendrier aujourd'hui. Profite de ton temps libre pour te ressourcer !")

    st.divider()

    # --- 2. GRAPHIQUES ET VUE D'ENSEMBLE ---
    st.header("Vue d'ensemble de ton blocus")
    
    if courses:
        # Couleurs associées aux cours pour les graphiques
        color_map = {c: st.session_state.courses[c]["color"] for c in courses}
        
        # --- PREPARATION DES DONNEES ---
        # Données Radar / Progression
        radar_data = [{"Cours": c, "Progression (%)": compute_progress(st.session_state.courses[c]["tasks"]) * 100} for c in courses]
        df_radar = pd.DataFrame(radar_data)
        
        # Données Camembert (Temps)
        pie_data = [{"Cours": c, "Jours alloués": study_days_count[c]["total"]} for c in courses if study_days_count[c]["total"] > 0]
        df_pie = pd.DataFrame(pie_data)
        
        # Données Barres (Points Acquis vs Objectifs)
        bar_data = []
        for c in courses:
            data = st.session_state.courses[c]
            earned = sum(g["score"] for g in data["grading"])
            tot_graded = sum(g["total"] for g in data["grading"])
            exam_tot = max(0, 20 - tot_graded)
            needed = max(0, 10 - earned)
            needed_from_exam = min(exam_tot, needed)
            bonus = max(0, exam_tot - needed_from_exam)
            
            bar_data.append({"Cours": c, "Type": "Acquis (déjà en poche)", "Points": earned})
            bar_data.append({"Cours": c, "Type": "À réussir à l'examen (pour 10/20)", "Points": needed_from_exam})
            bar_data.append({"Cours": c, "Type": "Bonus possible (pour la mention)", "Points": bonus})
            
        df_bar = pd.DataFrame(bar_data)

        # --- AFFICHAGE DES GRAPHIQUES ---
        col_chart1, col_chart2 = st.columns(2)
        
        with col_chart1:
            if len(courses) >= 3:
                # Graphique Radar (Toile d'araignée) - Il faut min 3 cours pour que ça ressemble à une toile
                fig_radar = px.line_polar(df_radar, r='Progression (%)', theta='Cours', line_close=True, title="Équilibre d'étude")
                fig_radar.update_traces(fill='toself', line_color="#4CAF50", fillcolor="rgba(76, 175, 80, 0.5)")
                fig_radar.update_layout(polar=dict(radialaxis=dict(range=[0, 100])))
                st.plotly_chart(fig_radar, use_container_width=True)
            else:
                # Alternative : un simple graphique en barres si tu as 1 ou 2 cours
                fig_prog = px.bar(df_radar, x="Cours", y="Progression (%)", color="Cours", color_discrete_map=color_map, title="Équilibre d'étude")
                fig_prog.update_layout(yaxis=dict(range=[0, 100]))
                st.plotly_chart(fig_prog, use_container_width=True)
                
        with col_chart2:
            # Diagramme Circulaire (Temps)
            if not df_pie.empty:
                fig_pie = px.pie(df_pie, values='Jours alloués', names='Cours', title="Répartition du temps de blocus", color='Cours', color_discrete_map=color_map, hole=0.4)
                st.plotly_chart(fig_pie, use_container_width=True)
            else:
                st.info("Planifie des jours d'étude dans le calendrier pour voir la répartition de ton temps !")

        # Graphique à barres empilées (Points)
        fig_bar_pts = px.bar(
            df_bar, x="Cours", y="Points", color="Type", 
            title="🎯 Stratégie des points (sur 20)",
            color_discrete_map={
                "Acquis (déjà en poche)": "#28a745", 
                "À réussir à l'examen (pour 10/20)": "#ffc107", 
                "Bonus possible (pour la mention)": "#e9ecef"
            }
        )
        fig_bar_pts.update_layout(barmode='stack', yaxis=dict(range=[0, 20]))
        st.plotly_chart(fig_bar_pts, use_container_width=True)

        st.divider()

        # Détail en barres textuelles
        col1, col2 = st.columns(2)
        for i, c in enumerate(courses):
            target_col = col1 if i % 2 == 0 else col2
            data = st.session_state.courses[c]
            with target_col:
                st.subheader(c)
                st.write(f"⏱️ **Prévus :** {study_days_count[c]['total']} jour(s) | ⏳ **Restants :** {study_days_count[c]['remaining']} jour(s)")
                progress_bar(compute_progress(data["tasks"]), data["color"])
                st.markdown("<br>", unsafe_allow_html=True)
    else:
        st.info("Ajoute des cours dans le menu de gauche pour commencer sur Bloc.us !")

# -------------------------
# 2. PLANNING / CALENDRIER
# -------------------------
with tab_objs[1]:
    col_head1, col_head2 = st.columns([3, 1])
    with col_head1:
        st.header("Programme d'étude")
    with col_head2:
        st.write("") 
        if st.button("🗑️ Vider le calendrier", use_container_width=True):
            st.session_state.schedule = {}
            auto_save()
            st.rerun()
    
    with st.expander("➕ Planifier une session", expanded=True):
        col1, col2, col3 = st.columns([2, 2, 3])
        selected_date = col1.date_input("Date")
        event_type = col2.selectbox("Type", ["Étude", "Examen"])
        selected_course = col3.selectbox("Cours concerné", courses if courses else ["Aucun cours"])
        
        # Le nouveau champ Description !
        desc = st.text_input("Description / Objectifs de la session (ex: Chapitre 5 et 6) - Optionnel")
        
        if st.button("Ajouter au calendrier", use_container_width=True):
            if courses:
                date_str = str(selected_date)
                if date_str not in st.session_state.schedule:
                    st.session_state.schedule[date_str] = []
                st.session_state.schedule[date_str].append({
                    "type": event_type, 
                    "course": selected_course,
                    "description": desc
                })
                auto_save()
                st.rerun()
            else:
                st.error("Ajoute d'abord un cours !")

    st.divider()

    def display_month_calendar(year, month):
        mois_noms = ["", "Janvier", "Février", "Mars", "Avril", "Mai", "Juin", "Juillet", "Août", "Septembre", "Octobre", "Novembre", "Décembre"]
        jours_noms = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]
        
        st.markdown(f"### {mois_noms[month]} {year}")
        cols = st.columns(7)
        for i, day in enumerate(jours_noms):
            cols[i].markdown(f"<div style='text-align:center; font-weight:bold; margin-bottom:10px;'>{day}</div>", unsafe_allow_html=True)
            
        cal = calendar.monthcalendar(year, month)
        for week in cal:
            cols = st.columns(7)
            for i, day in enumerate(week):
                if day != 0:
                    with cols[i].container(height=140, border=True):
                        st.markdown(f"<div style='font-weight:bold; text-align:right;'>{day}</div>", unsafe_allow_html=True)
                        date_str = f"{year}-{month:02d}-{day:02d}"
                        
                        if date_str in st.session_state.schedule:
                            for idx, ev in enumerate(st.session_state.schedule[date_str]):
                                course_data = st.session_state.courses.get(ev['course'], {})
                                color = course_data.get("color", "#4CAF50")
                                is_exam = (ev["type"] == "Examen")
                                icon = "🚨" if is_exam else "📚"
                                text_weight = "900" if is_exam else "500"
                                exam_text = "EXAM: " if is_exam else ""
                                
                                st.markdown(f"""
                                <div style="background-color: {color}33; border-left: 4px solid {color}; padding: 4px; border-radius: 4px; margin-bottom: 4px; font-size: 11px;">
                                    <span style="font-weight:{text_weight}; color: black;">{icon} {exam_text}{ev['course']}</span>
                                </div>
                                """, unsafe_allow_html=True)
                                
                else:
                    with cols[i].container(height=140, border=False):
                        st.empty()

    today = datetime.today()
    display_month_calendar(today.year, today.month)
    
    st.write("<br><br>", unsafe_allow_html=True)
    
    next_month = today.month + 1 if today.month < 12 else 1
    next_year = today.year if today.month < 12 else today.year + 1
    display_month_calendar(next_year, next_month)

# -------------------------
# 3. ONGLET PAR COURS
# -------------------------
for tab, cname in zip(tab_objs[2:], courses):
    with tab:
        data = st.session_state.courses[cname]
        tasks = data["tasks"]
        grading = data["grading"]
        color = data["color"]

        st.header(cname)
        
        with st.expander("⚙️ Modifier le nom ou la couleur"):
            new_name = st.text_input("Nouveau nom", value=cname, key=f"rn_{cname}")
            new_col = st.color_picker("Nouvelle couleur", value=color, key=f"cp_{cname}")
            
            if st.button("Enregistrer", key=f"save_edit_{cname}"):
                changed = False
                if new_col != color:
                    st.session_state.courses[cname]["color"] = new_col
                    changed = True
                    
                if new_name != cname and new_name.strip() != "":
                    if new_name not in st.session_state.courses:
                        st.session_state.courses[new_name] = st.session_state.courses.pop(cname)
                        for d_str, evs in st.session_state.schedule.items():
                            for e in evs:
                                if e["course"] == cname:
                                    e["course"] = new_name
                        changed = True
                    else:
                        st.error("Un cours avec ce nom existe déjà.")
                        st.stop()
                
                if changed:
                    auto_save()
                    st.rerun()

        progress_bar(compute_progress(tasks), color)

        # -- TÂCHES --
        with st.expander("➕ Ajouter tâche"):
            tname = st.text_input("Nom", key=f"t_{cname}")
            total = st.number_input("Total", 1, key=f"tt_{cname}")

            if st.button("Ajouter", key=f"add_t_{cname}"):
                tasks.append({"name": tname, "total": float(round(total, 2)), "done": 0.0})
                auto_save()
                st.rerun()

        for i, t in enumerate(tasks):
            st.markdown(f"#### {t['name']}")
            progress_bar(t["done"] / t["total"], color)

            cols = st.columns([2,1,1,1])
            cols[0].write(f"{round(t['done'],2)} / {round(t['total'],2)}")

            if cols[1].button("➖", key=f"m_{cname}_{i}"):
                if t["done"] > 0:
                    t["done"] = round(t["done"] - 1, 2)
                    auto_save()
                    st.rerun()

            if cols[2].button("➕", key=f"p_{cname}_{i}"):
                if t["done"] < t["total"]:
                    t["done"] = round(t["done"] + 1, 2)
                    auto_save()
                    st.rerun()

            if cols[3].button("❌", key=f"d_{cname}_{i}"):
                tasks.pop(i)
                auto_save()
                st.rerun()
            st.markdown("---")

        # -- PLANNING DU COURS --
        st.subheader("🗓️ Planification")
        st.write(f"⏱️ **Total prévu :** {study_days_count[cname]['total']} jour(s)")
        st.write(f"⏳ **Reste à faire :** {study_days_count[cname]['remaining']} jour(s)")
        
        st.markdown("<br>📅 **Dates planifiées :**", unsafe_allow_html=True)
        
        course_dates = []
        for d_str, events in st.session_state.schedule.items():
            for ev in events:
                if ev["course"] == cname:
                    d_obj = datetime.strptime(d_str, "%Y-%m-%d")
                    course_dates.append({"date_obj": d_obj, "type": ev["type"], "desc": ev.get("description", "")})
        
        course_dates.sort(key=lambda x: x["date_obj"])
        
        if course_dates:
            mois_noms_fr = ["", "Jan", "Fév", "Mar", "Avr", "Mai", "Juin", "Juil", "Août", "Sep", "Oct", "Nov", "Déc"]
            for item in course_dates:
                d = item["date_obj"]
                date_formatted = f"{d.day} {mois_noms_fr[d.month]} {d.year}"
                desc_text = f" *(Objectif: {item['desc']})*" if item['desc'] else ""
                
                if item["type"] == "Examen":
                    st.markdown(f"- 🚨 **{date_formatted} (Examen)**{desc_text}")
                else:
                    st.markdown(f"- 📚 {date_formatted}{desc_text}")
        else:
            st.write("- Aucun jour planifié dans le calendrier pour l'instant.")
        
        st.divider()

        # -- COTATION --
        st.subheader("🎓 Cotation")

        with st.expander("➕ Ajouter section"):
            name = st.text_input("Nom", key=f"g_{cname}")
            total = st.number_input("Sur combien de points", 1.0, key=f"gt_{cname}")
            score = st.number_input("Points obtenus", 0.0, key=f"gs_{cname}")

            if st.button("Ajouter section", key=f"add_g_{cname}"):
                grading.append({"name": name, "total": round(total, 2), "score": round(score, 2)})
                auto_save()
                st.rerun()

        for i, g in enumerate(grading):
            cols = st.columns([2,1,1,1])
            cols[0].write(f"**{g['name']} ({round(g['total'],2)} pts)**")

            new_score = cols[1].number_input("Score", value=float(g["score"]), key=f"s_{cname}_{i}")
            if new_score != g["score"]:
                g["score"] = new_score
                auto_save()

            cols[2].write(f"{round((g['total']/20)*100,2)} %")

            if cols[3].button("❌", key=f"dg_{cname}_{i}"):
                grading.pop(i)
                auto_save()
                st.rerun()

        # -- EXAMEN --
        exam_total, needed = compute_exam_needed(grading)
        st.divider()
        st.markdown("### 🧪 Examen")
        st.write(f"Examen sur **{exam_total:.2f} points**")

        if exam_total > 0:
            st.markdown(f"### 🎯 Tu dois avoir **{needed:.2f} / {exam_total:.2f}** pour réussir")
        else:
            st.success("🎉 Objectif déjà atteint !")