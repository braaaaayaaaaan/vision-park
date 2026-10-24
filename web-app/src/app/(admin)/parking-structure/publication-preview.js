'use client';
import { useEffect, useRef, useState } from 'react';
import shared from './parking-structure.module.css';
import styles from './publication-preview.module.css';
import useConfirmation from '../../../components/use-confirmation';

const number = value => value.toLocaleString('en-MY');
const statusLabels = { open: 'Open', closed: 'Closed', maintenance: 'Maintenance' };
// Only publisher-generated suffixes are removed from legacy display names.
const previousZoneName = name => name.replace(/\s+\[VP:[0-9a-f-]{36}\]$/i, '');

export default function PublicationPreview({ levelIds, disabled, onPublishingChange, onPublished }) {
  const [report,setReport]=useState(null),[choices,setChoices]=useState({}),[loading,setLoading]=useState(false),[error,setError]=useState('');
  const [choicesChanged,setChoicesChanged]=useState(false),[success,setSuccess]=useState('');
  const controller=useRef(null),pending=useRef(false);
  const levelName = id => [...(report?.levels ?? []), ...(report?.excluded_levels ?? [])].find(level => level.id === id)?.name ?? 'Unavailable level';
  function nodeLabel(id){
    const node=report?.proposed_graph.nodes.find(node=>node.id===id);
    return node?`${node.draft_code} (${levelName(node.level_id)})`:'Unavailable navigation point';
  }
  const activeTenants = report?.tenants.filter(tenant => tenant.is_active) ?? [];
  const accessZoneIds = new Set((report?.blocking_reasons ?? []).filter(reason => reason.code === 'tenant_permission_required' && report.zones.some(zone => zone.draft_zone_id === reason.zone_id)).map(reason => reason.zone_id));
  const otherBlockers = [...new Map((report?.blocking_reasons ?? []).filter(reason => !(reason.code === 'tenant_permission_required' && accessZoneIds.has(reason.zone_id)))
    .map(reason => [JSON.stringify(Object.entries(reason).sort(([a], [b]) => a.localeCompare(b))), reason])).values()];
  const levelOrder = new Map((report?.validation.levels ?? []).map(level => [level.id, level.level_number]));
  const sortedLevels = [...(report?.levels ?? [])].sort((a, b) => levelOrder.get(a.id) - levelOrder.get(b.id));
  const canPublish = Boolean(report?.can_publish && !disabled && !loading && !choicesChanged);
  const readiness = loading ? 'Processing Configuration' : report && (disabled || choicesChanged) ? 'Preview Requires Refresh' : report ? report.can_publish ? 'Ready to Publish' : 'Needs Attention' : success ? 'Published' : 'Preview Required';
  const readinessState = canPublish ? 'ready' : report && !choicesChanged && !disabled && !loading ? 'attention' : 'neutral';
  const rampConnections = report?.proposed_graph.directed_edges.filter(edge => edge.kind === 'cross_level').length ?? 0;
  const { requestConfirmation, confirmationDialog } = useConfirmation({ disabled: !canPublish, error });
  useEffect(()=>()=>{controller.current?.abort();onPublishingChange?.(false);},[onPublishingChange]);
  async function preview(){
    if(disabled||pending.current||!levelIds.length)return;
    pending.current=true;setLoading(true);setReport(null);setError('');setSuccess('');
    const request=new AbortController();controller.current=request;
    try{
      const response=await fetch('/api/parking-structure/publication/preview',{method:'POST',headers:{'Content-Type':'application/json'},
        body:JSON.stringify({level_ids:levelIds,tenant_permissions:Object.entries(choices).map(([zone_id,tenant_ids])=>({zone_id,tenant_ids}))}),cache:'no-store',signal:request.signal});
      if([401,403].includes(response.status)){window.location.replace(`/login?reason=${response.status===401?'expired':'denied'}`);return;}
      const data=await response.json();if(request.signal.aborted)return;
      if(!response.ok){setError((data.error??'Preview failed.')+(data.required_level_ids?.length?' Include the required ramp levels.':''));return;}
      setReport(data);setChoicesChanged(false);
    }catch(failure){if(!request.signal.aborted)setError(failure.message||'Publication preview could not be loaded.');}
    finally{pending.current=false;if(!request.signal.aborted)setLoading(false);}
  }
  async function publish(confirmed = false){
    if(disabled||pending.current||!report?.can_publish||choicesChanged)return;
    if(confirmed!==true)return requestConfirmation({ title: 'Publish Parking Configuration?',
      description: 'These changes will affect the entire parking facility.', variant: 'warning', confirmLabel: 'Publish Configuration',
      children: <><h3>What Will Change</h3><ul><li>Unselected parking levels will become inactive</li><li>Excluded parking zones will close</li><li>Existing driving routes will be replaced</li></ul>
        <h3>What Will Remain</h3><ul><li>Historical parking sessions will remain</li><li>Existing company access grants will remain</li></ul></>,
    },()=>publish(true));
    pending.current=true;setLoading(true);setError('');setSuccess('');onPublishingChange?.(true);
    const request=new AbortController();controller.current=request;
    try{
      const response=await fetch('/api/parking-structure/publication/publish',{method:'POST',headers:{'Content-Type':'application/json'},
        body:JSON.stringify({level_ids:levelIds,tenant_permissions:Object.entries(choices).map(([zone_id,tenant_ids])=>({zone_id,tenant_ids})),expected_fingerprint:report.fingerprint,confirm:true}),cache:'no-store',signal:request.signal});
      if([401,403].includes(response.status)){window.location.replace(`/login?reason=${response.status===401?'expired':'denied'}`);return;}
      const data=await response.json();if(request.signal.aborted)return;
      setReport(null);
      if(!response.ok){setError(data.error??'Publication was not confirmed. Refresh preview before retrying.');return false;}
      const message=`Successfully published the parking configurations! · Revision ${data.revision}`;setSuccess(message);onPublished?.(message);
    }catch{if(!request.signal.aborted){setError('Publication result is unknown. Refresh preview and review the recorded revision before retrying.');setReport(null);}return false;}
    finally{pending.current=false;onPublishingChange?.(false);if(!request.signal.aborted)setLoading(false);}
  }
  return <section className={styles.section} aria-label="Publication Preview" aria-busy={loading}>
    <div className={styles.heading}>
      <div><h3>Preview and Publish Configuration</h3><p>Review saved drafts and company access before activating the parking configuration.</p></div>
    </div>
    <ol className={styles.steps} aria-label="Publication Steps">
      {['Review Configuration', 'Assign Company Access', 'Refresh Preview', 'Publish Configuration'].map((step, index) => <li key={step}><span aria-hidden="true">{index + 1}</span>{step}</li>)}
    </ol>
    {error&&<p className={shared.error} role="alert">{error}</p>}
    {success&&<p className={shared.success} role="status">{success}</p>}
    {choicesChanged&&<p className={styles.notice} role="status">Company selections changed. Refresh the preview to check these choices before publishing. No permissions have been saved.</p>}
    {report&&<div className={styles.content}>
      <section className={styles.summary} aria-label="Configuration Summary">
        <div className={styles.sectionHeading}><h4>Configuration Summary</h4><span className={styles.badge} data-state={readinessState}>{readiness}</span></div>
        <dl className={styles.stats}>{[
          ['Selected Levels', report.levels.length], ['Parking Zones', report.zones.length],
          ['Usable Spaces', report.levels.reduce((total, level) => total + level.usable_destination_capacity, 0)],
          ['Navigation Points', report.proposed_graph.nodes.length], ['Driving Connections', report.proposed_graph.directed_edges.length],
        ].map(([label, value]) => <div key={label}><dt>{label}</dt><dd>{number(value)}</dd></div>)}</dl>
        <p className={styles.muted}>Usable spaces count open destinations only. This preview uses saved drafts, while company choices take effect only after publication.</p>
        <p className={styles.publishedState}>{report.publication_status==='published'?`Current published configuration: revision ${report.current_revision}.`:'No parking configuration has been published yet.'}</p>
      </section>

      {(accessZoneIds.size>0||otherBlockers.length>0)&&<section className={styles.attention} aria-label="Publication Blockers">
        <h4>Before You Publish</h4>
        {accessZoneIds.size>0&&<div><strong>{accessZoneIds.size} Parking {accessZoneIds.size===1?'Zone Requires':'Zones Require'} Company Access</strong><p>Select at least one authorised company for each open zone, then refresh the preview.</p></div>}
        {otherBlockers.length>0&&<ul className={styles.blockers}>{otherBlockers.map((reason,index)=>{
          const zone=report.zones.find(zone=>zone.draft_zone_id===reason.zone_id);
          return <li key={index}>{zone?<strong>{levelName(zone.level_id)} · {zone.name}</strong>:reason.level_id?<strong>{levelName(reason.level_id)}</strong>:null}<p>{reason.message}</p></li>;
        })}</ul>}
      </section>}

      <section className={styles.access} aria-label="Company Access by Level">
        <div><h4>Company Access by Level</h4><p className={styles.muted}>Select the companies authorised to use each zone. Existing access is retained. Checkbox changes are preview-only until you publish.</p></div>
        {sortedLevels.map(level=>{
          const zones=report.zones.filter(zone=>zone.level_id===level.id).sort((a,b)=>a.code.localeCompare(b.code,'en-MY',{numeric:true,sensitivity:'base'}));
          return <section className={styles.level} key={level.id} aria-label={`${level.name} company access`}>
            <div className={styles.levelHeading}><h5>{level.name}</h5><span>{zones.length} {zones.length===1?'Zone':'Zones'}</span></div>
            <div className={styles.zones}>{zones.map(zone=>{
              const requiresAccess=accessZoneIds.has(zone.draft_zone_id);
              return <article className={styles.zone} key={zone.draft_zone_id} aria-label={`${level.name} · ${zone.name}`}>
                <div className={styles.zoneHeading}><div><h6>{zone.name}</h6><p>{level.name} · Zone {zone.code}</p></div><span className={styles.badge} data-state="neutral">{statusLabels[zone.intended_status]??zone.intended_status}</span></div>
                <div className={styles.capacity}><strong>{number(zone.usable_capacity)}</strong><span>Usable Spaces</span></div>
                {requiresAccess&&<span className={styles.badge} data-state="attention">Company Access Required</span>}
                <fieldset className={styles.companies} disabled={disabled||loading}><legend>Authorised Companies</legend>{activeTenants.map(tenant=>{
                  const retained=zone.retained_tenant_ids.includes(tenant.id),selected=retained||(choices[zone.draft_zone_id]??[]).includes(tenant.id);
                  return <label key={tenant.id}><input type="checkbox" checked={selected} disabled={retained} onChange={event=>{
                    const next=event.target.checked?[...(choices[zone.draft_zone_id]??[]),tenant.id]:(choices[zone.draft_zone_id]??[]).filter(id=>id!==tenant.id);
                    setChoices(previous=>({...previous,[zone.draft_zone_id]:next}));setChoicesChanged(true);
                  }}/><span>{tenant.name}{retained&&<small>Existing access retained</small>}</span></label>;
                })}{!activeTenants.length&&<p className={styles.muted}>No active companies available.</p>}</fieldset>
              </article>;
            })}</div>
            {!zones.length&&<p className={styles.muted}>No parking zones in this level&apos;s preview.</p>}
          </section>;
        })}
      </section>

      <section className={styles.navigation} aria-label="Navigation Summary">
        <div className={styles.sectionHeading}><h4>Navigation Summary</h4><span className={styles.badge} data-state={report.validation.readiness==='ready'?'ready':'attention'}>{report.validation.readiness==='ready'?'Draft Checks Passed':'Draft Checks Require Attention'}</span></div>
        <dl className={styles.stats}>{[
          ['Navigation Points', report.proposed_graph.nodes.length],
          ['Directed Driving Connections', report.proposed_graph.directed_edges.length],
          ['Cross-Level Ramp Connections', rampConnections],
        ].map(([label, value]) => <div key={label}><dt>{label}</dt><dd>{number(value)}</dd></div>)}</dl>
        <p className={styles.muted}>Ramp connections are counted by travel direction. {report.validation.allocation_ready?'The saved draft is ready for allocation.':'The saved draft is not ready for allocation.'}</p>
      </section>

      <section className={styles.impact} aria-label="Publication Impact">
        <h4>Publication Impact</h4>
        <p>Publishing replaces the active parking configuration for the whole facility. It is not an independent update to one level. Selected levels become active and their driving routes replace the previous routes.</p>
        {report.excluded_levels.length>0&&<div><strong>{report.excluded_levels.length} {report.excluded_levels.length===1?'Level Will':'Levels Will'} Be Inactive</strong><p>These levels will be unavailable after publication:</p><ul className={styles.impactList}>{report.excluded_levels.map(level=><li key={level.id}>{level.name}</li>)}</ul></div>}
        {report.superseded_zones.length>0&&<div><strong>{report.superseded_zones.length} Existing Parking {report.superseded_zones.length===1?'Zone Will':'Zones Will'} Close</strong><p>These previous zones are not included in the new configuration. Their parking history and existing company access are retained.</p>
          <details className={styles.affected}><summary>View Affected Zones</summary><ul>{report.superseded_zones.map(zone=><li key={zone.id}>{levelName(zone.level_id)} · {previousZoneName(zone.name)}</li>)}</ul></details>
        </div>}
        <p className={styles.muted}>Existing parking session history is retained. This preview has not changed the operational configuration.</p>
      </section>

      <details className={styles.technical}><summary>Technical Details</summary>
        <div className={styles.technicalContent}>
          <p>Published revision: {report.current_revision} · Preview fingerprint: <code>{report.fingerprint}</code></p>
          <h5>Zone Identity and Entrance Mappings</h5>
          <ul>{report.zones.map(zone=><li key={zone.draft_zone_id}><strong>{levelName(zone.level_id)} · {zone.name}</strong><p>Draft ID: {zone.draft_zone_id} · Operational ID: {zone.operational_zone_id}</p><p>Operational code: {zone.operational_code}{zone.operational_name!==zone.name?` · Operational name: ${zone.operational_name}`:''}</p><p>{zone.action==='create_new'?'New identity':'Existing binding'} · Entrance: {zone.entrance_draft_node_id?nodeLabel(zone.entrance_draft_node_id):'Missing entrance mapping'}</p></li>)}</ul>
          <h5>Navigation Points</h5>
          <ul>{report.proposed_graph.nodes.map(node=><li key={node.id}>{nodeLabel(node.id)} · {node.node_type.replaceAll('_',' ')} · ({node.x}, {node.y}) original image pixels</li>)}</ul>
          <h5>Directed Driving Connections</h5>
          <ol>{report.proposed_graph.directed_edges.map(edge=><li key={`${edge.kind}-${edge.id}`}>{nodeLabel(edge.from_node_id)} to {nodeLabel(edge.to_node_id)}: {Number(edge.distance_meters).toLocaleString('en-MY',{maximumFractionDigits:8})} m ({edge.kind==='cross_level'?'Ramp':'Same level'})</li>)}</ol>
          <h5>Previous Configuration</h5>
          <p>{report.operational_graph.active_edges} active driving connections · {report.active_sessions} active sessions</p>
          <ul>{report.planned_cutover.map((action,index)=><li key={index}>{action}</li>)}</ul>
          <ul>{report.superseded_zones.map(zone=><li key={zone.id}>{levelName(zone.level_id)} · {previousZoneName(zone.name)}: {zone.historical_sessions} historical sessions · {zone.permission_count} existing company permissions retained</li>)}</ul>
        </div>
      </details>
    </div>}
    <div className={styles.publishActions}>
      <div role="status"><strong className={styles.readiness} data-state={readinessState}>{readiness}</strong><p>{loading?'Please wait while your request is confirmed.':report?disabled?'Save any configuration edits, then refresh the preview.':choicesChanged?'Refresh the preview to review your company selections.':report.can_publish?'Review the whole-facility impact before confirming publication.':'Resolve the issues above, then refresh the preview.':success?'The published configuration is now in use.':'Select Included Levels above, then prepare a preview of the saved drafts.'}</p></div>
      <div className={styles.actions}>
        <button type="button" className={shared.button} disabled={disabled||loading||!levelIds.length} onClick={preview}>{loading?'Please wait…':report?'Refresh Preview':'Preview Publication'}</button>
        <button type="button" className={`${shared.button} ${shared.primary}`} disabled={!canPublish} onClick={publish}>Publish Configuration</button>
      </div>
    </div>
    {confirmationDialog}
  </section>;
}
