export interface AgentItem { id: string; name: string; description: string; mode: string; hidden: boolean; model: string; }
export function selectableAgents(agents: AgentItem[], query: string = ''): AgentItem[] {
  const terms = query.trim().toLowerCase().split(/\s+/).filter((term: string) => !!term); const seen = new Set<string>();
  return agents.filter((agent: AgentItem) => {
    if (!agent.id || seen.has(agent.id) || agent.hidden || ['primary', 'all'].indexOf(agent.mode) < 0) { return false; }
    seen.add(agent.id); const text = (agent.id + ' ' + agent.name + ' ' + agent.description).toLowerCase();
    return terms.every((term: string) => text.indexOf(term) >= 0);
  });
}
